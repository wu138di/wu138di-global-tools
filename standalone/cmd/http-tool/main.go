// Native HTTP compatibility helper for this project's fixed device scripts.
// This is not curl, and deliberately does not implement curl's full CLI.
package main

import (
	"bufio"
	"context"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

type options struct {
	url, output, write, method, data, proxy, noproxy, agent, proto, redirProto string
	headers                                                                    http.Header
	connect, total                                                             time.Duration
	max                                                                        int64
	redirects, retries                                                         int
	follow, fail                                                               bool
}

func defaults() options {
	return options{method: "GET", headers: http.Header{}, connect: 15 * time.Second, total: 90 * time.Second, max: 8 * 1024 * 1024, redirects: 4}
}
func regular(path string, limit int64) ([]byte, error) {
	st, e := os.Lstat(path)
	if e != nil {
		return nil, e
	}
	if !st.Mode().IsRegular() || st.Size() > limit {
		return nil, errors.New("file rejected")
	}
	return os.ReadFile(path)
}
func header(o *options, value string) error {
	p := strings.SplitN(value, ":", 2)
	if len(p) != 2 || strings.ContainsAny(value, "\r\n") {
		return errors.New("header rejected")
	}
	o.headers.Add(strings.TrimSpace(p[0]), strings.TrimSpace(p[1]))
	return nil
}
func config(o *options, path string) error {
	body, e := regular(path, 65536)
	if e != nil {
		return e
	}
	s := bufio.NewScanner(strings.NewReader(string(body)))
	s.Buffer(make([]byte, 4096), 65536)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		pair := strings.SplitN(line, "=", 2)
		if len(pair) != 2 {
			return errors.New("config rejected")
		}
		key, value := strings.TrimSpace(pair[0]), strings.TrimSpace(pair[1])
		if strings.HasPrefix(value, `"`) {
			value, e = strconv.Unquote(value)
			if e != nil {
				return e
			}
		}
		switch key {
		case "header":
			if e = header(o, value); e != nil {
				return e
			}
		case "url":
			o.url = value
		default:
			return errors.New("config option rejected")
		}
	}
	return s.Err()
}
func parse(args []string) (options, error) {
	o := defaults()
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "--silent", "--show-error", "--disable", "-s", "-S", "-sS":
			continue
		case "--fail":
			o.fail = true
			continue
		case "--location":
			o.follow = true
			continue
		}
		if !strings.HasPrefix(a, "-") {
			if o.url != "" {
				return o, errors.New("multiple URLs rejected")
			}
			o.url = a
			continue
		}
		if i+1 >= len(args) {
			return o, errors.New("missing option value")
		}
		i++
		v := args[i]
		var e error
		switch a {
		case "--url":
			o.url = v
		case "--output", "-o":
			o.output = v
		case "--write-out", "-w":
			if v != "%{http_code}" {
				return o, errors.New("write format rejected")
			}
			o.write = v
		case "--request", "-X":
			o.method = v
		case "--data-binary":
			o.data = v
		case "--header", "-H":
			e = header(&o, v)
		case "--config", "-K":
			e = config(&o, v)
		case "--proxy":
			o.proxy = v
		case "--noproxy":
			if v != "" && v != "*" {
				return o, errors.New("noproxy rejected")
			}
			o.noproxy = v
		case "--user-agent", "-A":
			o.agent = v
		case "--proto":
			o.proto = v
		case "--proto-redir":
			o.redirProto = v
		case "--connect-timeout", "--max-time":
			var n float64
			n, e = strconv.ParseFloat(v, 64)
			if e == nil && (n <= 0 || n > 900) {
				e = errors.New("timeout rejected")
			}
			if a == "--connect-timeout" {
				o.connect = time.Duration(n * float64(time.Second))
			} else {
				o.total = time.Duration(n * float64(time.Second))
			}
		case "--max-filesize":
			o.max, e = strconv.ParseInt(v, 10, 64)
			if o.max <= 0 || o.max > 16*1024*1024 {
				e = errors.New("body limit rejected")
			}
		case "--retry":
			o.retries, e = strconv.Atoi(v)
			if o.retries < 0 || o.retries > 3 {
				e = errors.New("retry limit rejected")
			}
		case "--max-redirs":
			o.redirects, e = strconv.Atoi(v)
			if o.redirects < 0 || o.redirects > 8 {
				e = errors.New("redirect limit rejected")
			}
		default:
			return o, errors.New("unsupported option")
		}
		if e != nil {
			return o, e
		}
	}
	if o.method != "GET" && o.method != "POST" && o.method != "PUT" && o.method != "PATCH" && o.method != "DELETE" && o.method != "HEAD" {
		return o, errors.New("method rejected")
	}
	if o.proto != "" && o.proto != "=https" {
		return o, errors.New("protocol option rejected")
	}
	if o.redirProto != "" && o.redirProto != "=https" {
		return o, errors.New("redirect protocol rejected")
	}
	return o, nil
}
func allowed(raw string, httpsOnly bool) bool {
	u, e := url.Parse(raw)
	if e != nil || u.User != nil || u.Hostname() == "" {
		return false
	}
	if u.Scheme == "https" {
		return true
	}
	if !httpsOnly && u.Scheme == "http" {
		ip := net.ParseIP(u.Hostname())
		return ip != nil && (ip.IsLoopback() || ip.IsPrivate())
	}
	return false
}
func dialer(timeout time.Duration) *net.Dialer {
	d := &net.Dialer{Timeout: timeout}
	if runtime.GOOS == "android" {
		var n atomic.Uint32
		d.Resolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			targets := []string{"223.5.5.5:53", "119.29.29.29:53"}
			return (&net.Dialer{Timeout: 3 * time.Second}).DialContext(ctx, "udp", targets[(n.Add(1)-1)%2])
		}}
	}
	return d
}
func transfer(o options, stdout io.Writer) (int, int) {
	if !allowed(o.url, o.proto == "=https") {
		return 0, 2
	}
	tr := &http.Transport{DialContext: dialer(o.connect).DialContext, TLSHandshakeTimeout: o.connect, ResponseHeaderTimeout: o.total, DisableKeepAlives: true}
	defer tr.CloseIdleConnections()
	if o.proxy != "" && o.noproxy != "*" {
		u, e := url.Parse(o.proxy)
		if e != nil || u.Scheme != "http" || u.Hostname() != "127.0.0.1" {
			return 0, 2
		}
		tr.Proxy = http.ProxyURL(u)
	}
	client := &http.Client{Transport: tr, Timeout: o.total, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if !o.follow {
			return http.ErrUseLastResponse
		}
		if len(via) > o.redirects || !allowed(req.URL.String(), o.redirProto == "=https") {
			return errors.New("redirect rejected")
		}
		return nil
	}}
	var input io.Reader
	if o.data != "" {
		body := []byte(o.data)
		if strings.HasPrefix(o.data, "@") {
			var e error
			body, e = regular(o.data[1:], 8*1024*1024)
			if e != nil {
				return 0, 26
			}
		}
		input = strings.NewReader(string(body))
	}
	req, e := http.NewRequest(o.method, o.url, input)
	if e != nil {
		return 0, 2
	}
	req.Header = o.headers.Clone()
	if o.agent != "" {
		req.Header.Set("User-Agent", o.agent)
	}
	response, e := client.Do(req)
	if e != nil {
		var unknown x509.UnknownAuthorityError
		var invalid x509.CertificateInvalidError
		var ne net.Error
		switch {
		case errors.As(e, &unknown) || errors.As(e, &invalid):
			return 0, 60
		case errors.As(e, &ne) && ne.Timeout():
			return 0, 28
		default:
			return 0, 7
		}
	}
	defer response.Body.Close()
	status := response.StatusCode
	if o.fail && status >= 400 {
		return status, 22
	}
	if response.ContentLength > o.max {
		return status, 63
	}
	var dest io.Writer = stdout
	var file *os.File
	if o.output != "" {
		if st, e := os.Lstat(o.output); e == nil && !st.Mode().IsRegular() && o.output != "/dev/null" {
			return status, 23
		}
		file, e = os.OpenFile(o.output, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
		if e != nil {
			return status, 23
		}
		defer file.Close()
		dest = file
	}
	n, e := io.Copy(dest, io.LimitReader(response.Body, o.max+1))
	if n > o.max {
		return status, 63
	}
	if e != nil {
		return status, 23
	}
	if file != nil && o.output != "/dev/null" && file.Sync() != nil {
		return status, 23
	}
	return status, 0
}
func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == "--version" {
		fmt.Fprintln(stdout, "wu138di-http 1.1.0 (native HTTP helper; not curl)")
		return 0
	}
	o, e := parse(args)
	if e != nil {
		fmt.Fprintln(stderr, "HTTP_TOOL_OPTION_REJECTED")
		return 2
	}
	status, code := 0, 0
	for attempt := 0; attempt <= o.retries; attempt++ {
		status, code = transfer(o, stdout)
		if code == 0 || attempt == o.retries || code == 2 || code == 60 {
			break
		}
		time.Sleep(time.Second)
	}
	if o.write != "" {
		fmt.Fprintf(stdout, "%03d", status)
	}
	if code != 0 {
		fmt.Fprintf(stderr, "http-tool: (%d) request failed\n", code)
	}
	return code
}
func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }
