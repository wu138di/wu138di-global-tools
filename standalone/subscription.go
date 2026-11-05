package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var yamlProxies = regexp.MustCompile(`(?m)^(?:proxies|"proxies"|'proxies')\s*:`)

func publicHTTPS(raw string) bool {
	if !validSubscription(raw) {
		return false
	}
	u, _ := url.Parse(raw)
	host := strings.ToLower(u.Hostname())
	if host == "localhost" || strings.HasSuffix(host, ".localhost") {
		return false
	}
	if ip := net.ParseIP(host); ip != nil && (ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified()) {
		return false
	}
	return true
}

// Used only when the device's direct subscription download fails. It uses the
// already-running, explicitly configured local mixed proxy, never enables
// transparent capture, never changes system proxy, and retains TLS validation.
func proxySubscription(ctx context.Context, raw string) (string, error) {
	if !publicHTTPS(raw) {
		return "", errors.New("SUBSCRIPTION_URL_REJECTED")
	}
	proxy, _ := url.Parse("http://127.0.0.1:7890")
	tr := &http.Transport{Proxy: http.ProxyURL(proxy), TLSHandshakeTimeout: 15 * time.Second, ResponseHeaderTimeout: 30 * time.Second, DisableKeepAlives: true}
	defer tr.CloseIdleConnections()
	client := &http.Client{Transport: tr, Timeout: 90 * time.Second, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 4 || !publicHTTPS(req.URL.String()) {
			return errors.New("REDIRECT_REJECTED")
		}
		return nil
	}}
	req, e := http.NewRequestWithContext(ctx, "GET", raw, nil)
	if e != nil {
		return "", errors.New("SUBSCRIPTION_URL_REJECTED")
	}
	req.Header.Set("User-Agent", "clash.meta")
	response, e := client.Do(req)
	if e != nil {
		return "", errors.New("SUBSCRIPTION_PROXY_DOWNLOAD_FAILED")
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		if response.StatusCode == 403 {
			return "", errors.New("SUBSCRIPTION_HTTP_403")
		}
		return "", errors.New("SUBSCRIPTION_HTTP_FAILED")
	}
	body, e := io.ReadAll(io.LimitReader(response.Body, 1048577))
	if e != nil || len(body) > 1048576 || !yamlProxies.Match(body) {
		return "", errors.New("SUBSCRIPTION_FORMAT_INVALID")
	}
	return string(body), nil
}

type subscriptionSource struct {
	URL string `json:"url"`
}

func (d *androidDevice) sourcePath() string {
	return filepath.Join(d.home, "state", "subscription-source.json")
}
func (d *androidDevice) downloadSubscription(ctx context.Context, raw string) (string, error) {
	if d.download != nil {
		return d.download(ctx, raw)
	}
	return proxySubscription(ctx, raw)
}
func (d *androidDevice) source() (string, error) {
	data, e := safeFile(d.sourcePath(), 16384)
	if os.IsNotExist(e) {
		return "", nil
	}
	if e != nil {
		return "", errors.New("SUBSCRIPTION_SOURCE_INVALID")
	}
	var v subscriptionSource
	if json.Unmarshal(data, &v) != nil || !validSubscription(v.URL) {
		return "", errors.New("SUBSCRIPTION_SOURCE_INVALID")
	}
	return v.URL, nil
}
func (d *androidDevice) importNodes(ctx context.Context, q operation, stage func(string)) (any, error) {
	if e := d.management(ctx); e != nil {
		return nil, e
	}
	mode, input := "refresh", ""
	source := ""
	if q.Action == "import_yaml" {
		mode, input = "yaml", q.Value
	} else if q.Action == "import_subscription" {
		mode, input = "set", q.Value
	} else {
		var e error
		source, e = d.source()
		if e != nil {
			return nil, e
		}
	}
	if source != "" {
		stage("下载并校验订阅")
		body, e := d.downloadSubscription(ctx, source)
		if e != nil {
			return nil, e
		}
		_, e = d.run(ctx, "update", []string{"yaml"}, body)
		if e != nil {
			return nil, e
		}
		return map[string]bool{"ok": true}, nil
	}
	stage("下载并校验订阅")
	if mode == "yaml" {
		stage("校验 YAML")
	}
	_, e := d.run(ctx, "update", []string{mode}, input)
	if e != nil && mode == "set" && (e.Error() == "SUBSCRIPTION_HTTP_403" || e.Error() == "SUBSCRIPTION_DOWNLOAD_FAILED") {
		// First preserve a dormant candidate source; commit the selection pointer
		// only after the transactional YAML updater confirms live provider loading.
		stage("通过现有节点下载订阅")
		body, downloadErr := d.downloadSubscription(ctx, input)
		if downloadErr != nil {
			return nil, downloadErr
		}
		sourceBody, _ := json.Marshal(subscriptionSource{input})
		candidate := d.sourcePath() + ".candidate"
		if e = atomicFile(candidate, sourceBody, 0600); e != nil {
			return nil, errors.New("SUBSCRIPTION_SOURCE_SAVE_FAILED")
		}
		defer os.Remove(candidate)
		if _, e = d.run(ctx, "update", []string{"yaml"}, body); e != nil {
			return nil, e
		}
		if e = os.Rename(candidate, d.sourcePath()); e != nil {
			return nil, errors.New("SUBSCRIPTION_SOURCE_SAVE_FAILED")
		}
		return map[string]bool{"ok": true}, nil
	}
	if e != nil {
		return nil, e
	}
	if mode == "set" || mode == "yaml" {
		if e = os.Remove(d.sourcePath()); e != nil && !os.IsNotExist(e) {
			return nil, errors.New("SUBSCRIPTION_SOURCE_CLEAR_FAILED")
		}
	}
	return map[string]bool{"ok": true}, nil
}
