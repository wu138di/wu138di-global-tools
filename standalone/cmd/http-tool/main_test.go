package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestFixedCLIConfigAndBody(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer fixture" || r.Method != "PATCH" {
			t.Error("headers/method")
		}
		var body map[string]string
		if json.NewDecoder(r.Body).Decode(&body) != nil || body["mode"] != "rule" {
			t.Error("body")
		}
		w.WriteHeader(204)
	}))
	defer s.Close()
	d := t.TempDir()
	cfg := filepath.Join(d, "config")
	body := filepath.Join(d, "body")
	out := filepath.Join(d, "out")
	os.WriteFile(cfg, []byte("header = \"Authorization: Bearer fixture\"\n"), 0600)
	os.WriteFile(body, []byte(`{"mode":"rule"}`), 0600)
	var stdout, stderr bytes.Buffer
	code := run([]string{"--silent", "--noproxy", "*", "--config", cfg, "--request", "PATCH", "--data-binary", "@" + body, "--output", out, "--write-out", "%{http_code}", s.URL}, &stdout, &stderr)
	if code != 0 || stdout.String() != "204" {
		t.Fatalf("code %d: %s %s", code, &stdout, &stderr)
	}
}
func TestHTTPFailureAndBodyLimit(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/fail" {
			w.WriteHeader(403)
			return
		}
		w.Write([]byte("123456789"))
	}))
	defer s.Close()
	for _, q := range []struct {
		args []string
		want int
	}{{[]string{"--fail", s.URL + "/fail"}, 22}, {[]string{"--max-filesize", "3", s.URL}, 63}, {[]string{"--insecure", s.URL}, 2}, {[]string{"--proto", "=https", s.URL}, 2}} {
		var a, b bytes.Buffer
		if code := run(q.args, &a, &b); code != q.want {
			t.Fatalf("code %d want %d", code, q.want)
		}
	}
}
func TestUntrustedTLSIsRejected(t *testing.T) {
	s := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }))
	defer s.Close()
	var a, b bytes.Buffer
	if code := run([]string{s.URL}, &a, &b); code != 60 {
		t.Fatalf("TLS code %d", code)
	}
}
func TestHTTPSRedirectDowngradeRejected(t *testing.T) {
	if allowed("http://8.8.8.8", false) || allowed("http://127.0.0.1", true) || allowed("file:///etc/passwd", false) {
		t.Fatal("protocol leak")
	}
	if !allowed("http://192.168.0.1:9090/configs", false) {
		t.Fatal("controller rejected")
	}
}
