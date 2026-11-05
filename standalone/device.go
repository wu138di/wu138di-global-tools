package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

type androidDevice struct {
	home, variant string
	runMu         sync.Mutex
	invoke        func(context.Context, string, []string, string) (string, error)
	download      func(context.Context, string) (string, error)
}
type boundedOutput struct {
	bytes.Buffer
	full bool
}

func (b *boundedOutput) Write(p []byte) (int, error) {
	n := len(p)
	room := 4*1024*1024 - b.Len()
	if room < 0 {
		room = 0
	}
	if len(p) > room {
		b.full = true
		p = p[:room]
	}
	_, _ = b.Buffer.Write(p)
	return n, nil
}

var fixedFailure = regexp.MustCompile(`(?m)^U30_PLUGIN_ERROR: ([A-Z0-9_]{1,96})\s*$`)

func (d *androidDevice) run(ctx context.Context, name string, args []string, input string) (string, error) {
	// Only developer-owned script names reach exec; all user data is argv or stdin.
	d.runMu.Lock()
	defer d.runMu.Unlock()
	if d.invoke != nil {
		return d.invoke(ctx, name, args, input)
	}
	allowed := map[string]string{"bridge": "engine-api.sh", "adopt": "adopt-runtime.sh", "install": "install.sh", "repair": "repair-network.sh", "standard": "restore-standard.sh", "update": "/data/adb/u30proxy/update.sh"}
	path, ok := allowed[name]
	if !ok {
		return "", errors.New("OPERATION_REJECTED")
	}
	if !filepath.IsAbs(path) {
		path = filepath.Join(d.home, "scripts", path)
	}
	if _, e := safeFile(path, 300000); e != nil {
		return "", errors.New("DEVICE_COMPONENT_MISSING")
	}
	cmd := exec.CommandContext(ctx, "/system/bin/sh", append([]string{path}, args...)...)
	cmd.Stdin = strings.NewReader(input)
	cmd.Env = []string{"PATH=/system/bin:/system/xbin:/vendor/bin", "HOME=" + d.home, "LC_ALL=C", "U30_OFFLINE_DIR=" + filepath.Join(d.home, "offline")}
	var out boundedOutput
	cmd.Stdout = &out
	cmd.Stderr = &out
	e := cmd.Run()
	output := strings.ReplaceAll(out.String(), "\r", "")
	if e != nil {
		if m := fixedFailure.FindStringSubmatch(output); m != nil {
			return "", errors.New(m[1])
		}
		if name == "update" {
			codes := map[string]string{"download_http_403": "SUBSCRIPTION_HTTP_403", "download_http_401": "SUBSCRIPTION_HTTP_401", "download_failed": "SUBSCRIPTION_DOWNLOAD_FAILED", "format_rejected": "SUBSCRIPTION_FORMAT_INVALID", "test_failed": "SUBSCRIPTION_FORMAT_INVALID", "api_failed": "SUBSCRIPTION_LOAD_FAILED", "busy": "JOB_BUSY"}
			for _, line := range strings.Split(output, "\n") {
				if code, ok := codes[strings.TrimSpace(line)]; ok {
					return "", errors.New(code)
				}
			}
		}
		if ctx.Err() != nil {
			return "", errors.New("DEVICE_TIMEOUT")
		}
		return "", errors.New("DEVICE_COMMAND_FAILED")
	}
	if out.full {
		return "", errors.New("DEVICE_RESPONSE_TOO_LARGE")
	}
	return strings.TrimSpace(output), nil
}
func (d *androidDevice) bridge(ctx context.Context, op string, args ...string) (string, error) {
	return d.run(ctx, "bridge", append([]string{op}, args...), "")
}
func (d *androidDevice) object(ctx context.Context, op string, args ...string) (map[string]any, error) {
	text, e := d.bridge(ctx, op, args...)
	if e != nil {
		return nil, e
	}
	var v map[string]any
	if json.Unmarshal([]byte(text), &v) != nil || v == nil {
		return nil, errors.New("DEVICE_DATA_INVALID")
	}
	return v, nil
}
func lines(text string) map[string]string {
	v := map[string]string{}
	for _, l := range strings.Split(text, "\n") {
		p := strings.SplitN(l, "=", 2)
		if len(p) == 2 {
			v[p[0]] = p[1]
		}
	}
	return v
}
func (d *androidDevice) status(ctx context.Context) (map[string]string, error) {
	text, e := d.bridge(ctx, "status")
	if e != nil {
		return nil, e
	}
	raw := lines(text)
	v := map[string]string{}
	for _, key := range []string{"deployment", "core", "enabled", "transparent", "autostart", "subscription", "controller", "input_protection", "admin", "watchdog", "regional_rules", "domestic_rules"} {
		if s, ok := raw[key]; ok {
			v[key] = s
		}
	}
	if v["core"] == "" && v["deployment"] != "missing" {
		return nil, errors.New("DEVICE_STATUS_UNCONFIRMED")
	}
	return v, nil
}
func mapObject(v any) map[string]any {
	m, _ := v.(map[string]any)
	if m == nil {
		return map[string]any{}
	}
	return m
}
func (d *androidDevice) nodes(ctx context.Context) (map[string]any, map[string]string, error) {
	a, e := d.object(ctx, "proxies")
	if e != nil {
		return nil, nil, e
	}
	b, e := d.object(ctx, "providers")
	if e != nil {
		return nil, nil, e
	}
	nodes := mapObject(a["proxies"])
	owners := map[string]string{}
	for provider, p := range mapObject(b["providers"]) {
		list, _ := mapObject(p)["proxies"].([]any)
		for _, n := range list {
			item := mapObject(n)
			name, _ := item["name"].(string)
			if name != "" {
				owners[name] = provider
				if _, ok := nodes[name]; !ok {
					nodes[name] = item
				}
			}
		}
	}
	clean := map[string]any{}
	for name, n := range nodes {
		v := mapObject(n)
		item := map[string]any{}
		for _, k := range []string{"name", "type", "history", "all", "now", "alive", "udp", "tfo", "mptcp"} {
			if x, ok := v[k]; ok {
				item[k] = x
			}
		}
		clean[name] = item
	}
	return clean, owners, nil
}
func (d *androidDevice) snapshot(ctx context.Context) (any, error) {
	state, e := d.status(ctx)
	if e != nil {
		return nil, e
	}
	v := map[string]any{"status": state, "mode": "rule", "proxies": map[string]any{}, "rules": []any{}, "connections": map[string]any{"connections": []any{}, "downloadTotal": 0, "uploadTotal": 0, "memory": 0}}
	if state["deployment"] == "missing" || state["core"] != "running" || state["subscription"] != "validated" || state["controller"] != "authenticated-ready" {
		if state["subscription"] == "validated" {
			return loadNodes(d.home, providerHash(), v), nil
		}
		return v, nil
	}
	mode, e := d.object(ctx, "mode")
	if e != nil {
		return nil, e
	}
	nodes, _, e := d.nodes(ctx)
	if e != nil {
		return nil, e
	}
	rules, e := d.object(ctx, "rules")
	if e != nil {
		return nil, e
	}
	conn, e := d.object(ctx, "connections")
	if e != nil {
		return nil, e
	}
	switch mode["mode"] {
	case "rule", "global", "direct":
	default:
		return nil, errors.New("MODE_INVALID")
	}
	if conn["connections"] == nil {
		conn["connections"] = []any{}
	}
	v["mode"] = mode["mode"]
	v["proxies"] = nodes
	v["rules"] = rules["rules"]
	v["connections"] = conn
	saveNodes(d.home, providerHash(), v)
	return v, nil
}
func (d *androidDevice) delay(ctx context.Context, name string) (any, error) {
	_, owners, e := d.nodes(ctx)
	if e != nil {
		return nil, e
	}
	return d.probe(ctx, name, owners[name])
}
func (d *androidDevice) probe(ctx context.Context, name, provider string) (any, error) {
	op := "delay"
	args := []string{url.PathEscape(name)}
	if provider != "" {
		op = "provider_delay"
		args = []string{url.PathEscape(provider), url.PathEscape(name)}
	}
	value, e := d.object(ctx, op, args...)
	if e != nil {
		return nil, errors.New("NODE_UNREACHABLE")
	}
	n, ok := value["delay"].(float64)
	if !ok || n <= 0 {
		return nil, errors.New("NODE_UNREACHABLE")
	}
	return map[string]any{"delay": n, "measuredAt": time.Now().UnixMilli()}, nil
}
func (d *androidDevice) Read(ctx context.Context, op string, args []string) (any, error) {
	switch op {
	case "snapshot":
		return d.snapshot(ctx)
	case "status":
		return d.status(ctx)
	case "proxies":
		v, _, e := d.nodes(ctx)
		return v, e
	case "rules":
		v, e := d.object(ctx, "rules")
		return v["rules"], e
	case "connections":
		return d.object(ctx, "connections")
	case "diagnostics":
		v, e := d.bridge(ctx, "diagnostics")
		return lines(v), e
	case "delay":
		return d.delay(ctx, args[0])
	}
	return nil, errors.New("OPERATION_REJECTED")
}
func (d *androidDevice) management(ctx context.Context) error {
	state, e := d.status(ctx)
	if e != nil {
		return e
	}
	if state["deployment"] == "missing" {
		return errors.New("DEPLOYMENT_MISSING")
	}
	if state["core"] != "running" {
		_, e = d.bridge(ctx, "management_start")
	}
	return e
}
func validSubscription(value string) bool {
	if !validText(value, 8192) || strings.TrimSpace(value) != value || strings.ContainsAny(value, " \t\r\n") {
		return false
	}
	u, e := url.Parse(value)
	return e == nil && u.Scheme == "https" && u.Hostname() != "" && u.User == nil && u.Fragment == ""
}
func (d *androidDevice) Mutate(ctx context.Context, q operation, stage func(string)) (any, error) {
	stage("处理中")
	switch q.Action {
	case "set_mode":
		return d.object(ctx, "set_mode", q.Args[0])
	case "select":
		return d.object(ctx, "select", url.PathEscape(q.Args[0]), mustJSON(map[string]string{"name": q.Args[1]}))
	case "close_connection":
		return d.object(ctx, "close_connection", url.PathEscape(q.Args[0]))
	case "autostart":
		_, e := d.bridge(ctx, "autostart", q.Args[0])
		return map[string]bool{"ok": e == nil}, e
	case "install":
		before, e := d.status(ctx)
		if e != nil {
			return nil, e
		}
		if before["transparent"] == "on" {
			return nil, errors.New("STOP_PROXY_BEFORE_INSTALL")
		}
		stage("校验离线组件")
		if _, e = d.run(ctx, "adopt", nil, ""); e != nil {
			return nil, e
		}
		_, installErr := d.run(ctx, "install", nil, "")
		// Restore the capture/autostart state even when an installation stage fails.
		if before["autostart"] != "yes" {
			_, _ = d.bridge(ctx, "autostart", "no")
		}
		if before["deployment"] == "missing" || before["core"] == "stopped" {
			_, _ = d.bridge(ctx, "disable")
			_, _ = d.bridge(ctx, "stop")
		}
		if installErr != nil {
			return nil, installErr
		}
		return map[string]bool{"ok": true}, nil
	case "import_yaml", "import_subscription", "refresh":
		return d.importNodes(ctx, q, stage)
	case "standard":
		stage("备份并更新规则")
		_, e := d.run(ctx, "standard", nil, "")
		return map[string]bool{"ok": e == nil}, e
	case "rollback_rules":
		_, e := d.bridge(ctx, "rollback_rules")
		return map[string]bool{"ok": e == nil}, e
	case "enable":
		before, e := d.status(ctx)
		if e != nil {
			return nil, e
		}
		if before["transparent"] == "on" {
			return map[string]bool{"ok": true}, nil
		}
		if before["subscription"] != "validated" {
			return nil, errors.New("IMPORT_NODES_FIRST")
		}
		if e = d.management(ctx); e != nil {
			return nil, e
		}
		stage("检查出口与 DNS")
		if _, e = d.run(ctx, "repair", nil, ""); e != nil {
			return nil, e
		}
		nodes, owners, e := d.nodes(ctx)
		if e != nil {
			return nil, e
		}
		mode, e := d.object(ctx, "mode")
		if e != nil {
			return nil, e
		}
		node := "PROXY"
		if mode["mode"] == "global" {
			node = "GLOBAL"
		}
		visited := map[string]bool{}
		for {
			v, ok := nodes[node]
			if !ok {
				return nil, errors.New("SELECT_NODE_FIRST")
			}
			item := mapObject(v)
			if _, group := item["all"].([]any); !group {
				break
			}
			if visited[node] || len(visited) > 12 {
				return nil, errors.New("PROXY_GROUP_CYCLE")
			}
			visited[node] = true
			node, _ = item["now"].(string)
		}
		switch mapObject(nodes[node])["type"] {
		case "Direct", "Reject", "RejectDrop", "Pass", "Compatible", "DNS":
			return nil, errors.New("SELECT_NODE_FIRST")
		}
		stage("验证代理链路")
		if _, e = d.probe(ctx, node, owners[node]); e != nil {
			return nil, e
		}
		text, e := d.bridge(ctx, "diagnostics")
		network := lines(text)
		if e != nil || network["route"] != "ready" || !strings.HasPrefix(network["proxy_http"], "20") {
			return nil, errors.New("PROXY_NOT_READY_DIRECT_PRESERVED")
		}
		stage("启用透明代理")
		_, e = d.bridge(ctx, "enable")
		if e != nil {
			return nil, e
		}
		after, e := d.status(ctx)
		if e != nil || after["transparent"] != "on" {
			_, _ = d.bridge(ctx, "disable")
			return nil, errors.New("CAPTURE_NOT_CONFIRMED")
		}
		return map[string]bool{"ok": true}, nil
	case "start", "disable", "restart", "stop":
		_, e := d.bridge(ctx, q.Action)
		return map[string]bool{"ok": e == nil}, e
	}
	return nil, errors.New("OPERATION_REJECTED")
}

// Loopback-only development mode exercises the real HTTP/auth/UI stack. It does
// not invent nodes, delays, device state, or successful device operations.
type offlineDevice struct{}

func (offlineDevice) Read(_ context.Context, op string, _ []string) (any, error) {
	if op == "status" {
		return map[string]string{"deployment": "missing", "core": "stopped", "transparent": "off", "autostart": "no"}, nil
	}
	if op == "snapshot" {
		return map[string]any{"status": map[string]string{"deployment": "missing", "core": "stopped", "transparent": "off", "autostart": "no"}, "mode": "rule", "proxies": map[string]any{}, "rules": []any{}, "connections": map[string]any{"connections": []any{}}}, nil
	}
	return nil, errors.New("ANDROID_DEVICE_REQUIRED")
}
func (offlineDevice) Mutate(context.Context, operation, func(string)) (any, error) {
	return nil, errors.New("ANDROID_DEVICE_REQUIRED")
}

var _ = fmt.Sprintf
var _ = os.ErrNotExist
