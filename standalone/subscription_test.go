package main

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
)

func TestSubscription403FallbackAndRefresh(t *testing.T) {
	source := "https://example.invalid/private-subscription"
	yaml := "proxies:\n  - name: fixture\n    type: ss\n"
	downloads, yamlImports := 0, 0
	d := androidDevice{home: t.TempDir(), download: func(_ context.Context, raw string) (string, error) {
		if raw != source {
			t.Fatal("source changed")
		}
		downloads++
		return yaml, nil
	}}
	d.invoke = func(_ context.Context, name string, args []string, input string) (string, error) {
		if name == "bridge" && args[0] == "status" {
			return "core=running\ntransparent=off", nil
		}
		if name != "update" {
			t.Fatal("unexpected command")
		}
		if args[0] == "set" {
			return "", errors.New("SUBSCRIPTION_HTTP_403")
		}
		if args[0] == "yaml" && input == yaml {
			yamlImports++
			return "committed", nil
		}
		t.Fatal("stale or wrong import")
		return "", nil
	}
	if _, e := d.Mutate(context.Background(), operation{Action: "import_subscription", Value: source}, func(string) {}); e != nil {
		t.Fatal(e)
	}
	if s, e := d.source(); e != nil || s != source {
		t.Fatal("new source not persisted")
	}
	if _, e := d.Mutate(context.Background(), operation{Action: "refresh"}, func(string) {}); e != nil {
		t.Fatal(e)
	}
	if downloads != 2 || yamlImports != 2 {
		t.Fatal("fallback/refresh not used")
	}
	if _, e := d.Mutate(context.Background(), operation{Action: "import_yaml", Value: yaml}, func(string) {}); e != nil {
		t.Fatal(e)
	}
	if _, e := os.Stat(d.sourcePath()); !os.IsNotExist(e) {
		t.Fatal("old URL survives local YAML import")
	}
}
func TestFailedSubscriptionPreservesSource(t *testing.T) {
	d := androidDevice{home: t.TempDir(), invoke: func(_ context.Context, name string, args []string, _ string) (string, error) {
		if name == "bridge" {
			return "core=running", nil
		}
		return "", errors.New("SUBSCRIPTION_HTTP_403")
	}, download: func(context.Context, string) (string, error) {
		return "", errors.New("SUBSCRIPTION_PROXY_DOWNLOAD_FAILED")
	}}
	if e := atomicFile(d.sourcePath(), []byte(`{"url":"https://example.invalid/previous"}`), 0600); e != nil {
		t.Fatal(e)
	}
	if _, e := d.Mutate(context.Background(), operation{Action: "import_subscription", Value: "https://example.invalid/new"}, func(string) {}); e == nil {
		t.Fatal("failed download reported success")
	}
	if s, _ := d.source(); !strings.HasSuffix(s, "/previous") {
		t.Fatal("old source lost")
	}
}
func TestSubscriptionHTTPSAndRedirectBounds(t *testing.T) {
	for _, raw := range []string{"http://example.invalid/x", "https://127.0.0.1/x", "https://192.168.0.1/x", "https://localhost/x", "https://[::1]/x", "https://user:pass@example.invalid/x"} {
		if publicHTTPS(raw) {
			t.Fatalf("unsafe subscription accepted %s", raw)
		}
	}
	if !publicHTTPS("https://example.invalid/s/test") {
		t.Fatal("normal HTTPS rejected")
	}
}
