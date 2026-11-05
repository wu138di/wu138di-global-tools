package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeDevice struct {
	mu    sync.Mutex
	calls []operation
	wait  chan struct{}
}

func (f *fakeDevice) Read(_ context.Context, op string, args []string) (any, error) {
	f.mu.Lock()
	f.calls = append(f.calls, operation{Action: op, Args: args})
	f.mu.Unlock()
	return map[string]bool{"ok": true}, nil
}
func (f *fakeDevice) Mutate(ctx context.Context, q operation, stage func(string)) (any, error) {
	f.mu.Lock()
	f.calls = append(f.calls, q)
	f.mu.Unlock()
	stage("校验")
	if f.wait != nil {
		select {
		case <-f.wait:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	if q.Action == "standard" {
		return nil, errors.New("private URL https://secret.invalid/token")
	}
	return map[string]bool{"ok": true}, nil
}
func testApp(t *testing.T) (*app, *fakeDevice) {
	t.Helper()
	f := &fakeDevice{}
	return newApp(f, "127.0.0.1:9088", filepath.Join(t.TempDir(), "state", "pin.json"), false), f
}
func requestTest(a *app, method, path, body string, cookie *http.Cookie, csrf string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "http://"+a.host+path, strings.NewReader(body))
	r.RemoteAddr = "127.0.0.1:12345"
	r.Header.Set("Content-Type", "application/json")
	if method == "POST" {
		r.Header.Set("Origin", a.origin)
	}
	if cookie != nil {
		r.AddCookie(cookie)
	}
	if csrf != "" {
		r.Header.Set("X-CSRF-Token", csrf)
	}
	w := httptest.NewRecorder()
	a.ServeHTTP(w, r)
	return w
}
func loginTest(t *testing.T, a *app, pin string) (*http.Cookie, string) {
	t.Helper()
	w := requestTest(a, "POST", "/api/login", mustJSON(map[string]string{"pin": pin}), nil, "")
	if w.Code != 200 {
		t.Fatalf("login=%d %s", w.Code, w.Body.String())
	}
	var v map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &v)
	return w.Result().Cookies()[0], v["csrf"].(string)
}
func waitJob(t *testing.T, a *app) {
	t.Helper()
	for i := 0; i < 200; i++ {
		a.mu.Lock()
		done := a.current != nil && a.current.State != "running"
		a.mu.Unlock()
		if done {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("job timeout")
}
func TestNoLoginNoDeviceAccess(t *testing.T) {
	a, f := testApp(t)
	for _, p := range []string{"/api/read", "/api/action", "/api/job", "/api/pin/change"} {
		w := requestTest(a, "POST", p, `{"action":"enable"}`, nil, "")
		if w.Code != 401 {
			t.Fatalf("%s=%d", p, w.Code)
		}
	}
	if len(f.calls) != 0 {
		t.Fatal("unauthenticated device access")
	}
}
func TestHostOriginRemoteAndMethods(t *testing.T) {
	a, _ := testApp(t)
	for _, tc := range []struct{ host, origin, remote, method string }{{"attacker.invalid", "", "127.0.0.1:1", "GET"}, {a.host, "http://evil.invalid", "127.0.0.1:1", "GET"}, {a.host, "", "8.8.8.8:1", "GET"}, {a.host, "", "127.0.0.1:1", "POST"}, {a.host, "", "127.0.0.1:1", "DELETE"}} {
		r := httptest.NewRequest(tc.method, "http://"+a.host+"/api/login", strings.NewReader(`{}`))
		r.Host = tc.host
		r.RemoteAddr = tc.remote
		r.Header.Set("Origin", tc.origin)
		w := httptest.NewRecorder()
		a.ServeHTTP(w, r)
		if w.Code < 400 {
			t.Fatalf("accepted %+v", tc)
		}
	}
}
func TestCookieCSRFAndLogout(t *testing.T) {
	a, _ := testApp(t)
	a.secure = true
	c, csrf := loginTest(t, a, "2007")
	if !c.HttpOnly || !c.Secure || c.SameSite != http.SameSiteStrictMode {
		t.Fatal("cookie flags")
	}
	for _, token := range []string{"", "bad"} {
		if w := requestTest(a, "POST", "/api/read", `{"action":"status"}`, c, token); w.Code != 403 {
			t.Fatal("csrf")
		}
	}
	if w := requestTest(a, "POST", "/api/read", `{"action":"status"}`, c, csrf); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if w := requestTest(a, "POST", "/api/logout", `{}`, c, csrf); w.Code != 200 {
		t.Fatal("logout")
	}
	if w := requestTest(a, "POST", "/api/read", `{"action":"status"}`, c, csrf); w.Code != 401 {
		t.Fatal("session survived logout")
	}
}
func TestLoginRateLimitAndExpiry(t *testing.T) {
	a, _ := testApp(t)
	for i := 0; i < 5; i++ {
		if w := requestTest(a, "POST", "/api/login", `{"pin":"wrong"}`, nil, ""); w.Code != 401 {
			t.Fatal("wrong pin status")
		}
	}
	if w := requestTest(a, "POST", "/api/login", `{"pin":"2007"}`, nil, ""); w.Code != 429 {
		t.Fatal("no login rate limit")
	}
	a.mu.Lock()
	a.failures = map[string]attempts{}
	a.mu.Unlock()
	c, csrf := loginTest(t, a, "2007")
	a.mu.Lock()
	s := a.sessions[c.Value]
	s.Expires = time.Now().Add(-time.Second)
	a.sessions[c.Value] = s
	a.mu.Unlock()
	if w := requestTest(a, "POST", "/api/read", `{"action":"status"}`, c, csrf); w.Code != 401 {
		t.Fatal("expired session")
	}
}
func TestPINChangePersistenceAndRevocation(t *testing.T) {
	a, _ := testApp(t)
	c, csrf := loginTest(t, a, "2007")
	second, other := loginTest(t, a, "2007")
	if w := requestTest(a, "POST", "/api/pin/change", `{"current":"bad!","next":"new-pass-9","confirm":"new-pass-9"}`, c, csrf); w.Code != 403 {
		t.Fatal("wrong current accepted")
	}
	w := requestTest(a, "POST", "/api/pin/change", `{"current":"2007","next":"new-pass-9","confirm":"new-pass-9"}`, c, csrf)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	b, e := os.ReadFile(a.pinPath)
	if e != nil || strings.Contains(string(b), "new-pass-9") {
		t.Fatal("plaintext pin persisted")
	}
	for _, pair := range []struct {
		c *http.Cookie
		s string
	}{{c, csrf}, {second, other}} {
		if w := requestTest(a, "POST", "/api/read", `{"action":"status"}`, pair.c, pair.s); w.Code != 401 {
			t.Fatal("old session survived")
		}
	}
	if w := requestTest(a, "POST", "/api/login", `{"pin":"2007"}`, nil, ""); w.Code != 401 {
		t.Fatal("old default still accepted")
	}
	loginTest(t, a, "new-pass-9")
	status := requestTest(a, "GET", "/api/pin/status", "", nil, "")
	if !strings.Contains(status.Body.String(), `"configured":true`) {
		t.Fatal("default hint not removed")
	}
	p, e := readProfile(a.pinPath)
	if e != nil || !matchesPIN("new-pass-9", p) {
		t.Fatal("profile not persistent")
	}
}
func TestCorruptPINDoesNotFallBack(t *testing.T) {
	a, _ := testApp(t)
	if e := atomicFile(a.pinPath, []byte(`{"broken":true}`), 0600); e != nil {
		t.Fatal(e)
	}
	if w := requestTest(a, "POST", "/api/login", `{"pin":"2007"}`, nil, ""); w.Code != 503 {
		t.Fatal("corrupt profile defaulted")
	}
}
func TestAllowedOperationsAndPrivateOutput(t *testing.T) {
	a, f := testApp(t)
	c, csrf := loginTest(t, a, "2007")
	for _, body := range []string{`{"action":"shell","value":"id"}`, `{"action":"set_mode","args":["global;id"]}`, `{"action":"import_subscription","value":"http://evil.invalid/x"}`, `{"action":"stop","command":"id"}`, `{"action":"autostart","args":["yes;id"]}`, `{"action":"install","value":"curl bad"}`} {
		if w := requestTest(a, "POST", "/api/action", body, c, csrf); w.Code != 400 {
			t.Fatalf("operation accepted %s", body)
		}
	}
	if len(f.calls) != 0 {
		t.Fatal("invalid operation reached device")
	}
	if w := requestTest(a, "POST", "/api/action", `{"action":"standard"}`, c, csrf); w.Code != 202 {
		t.Fatal(w.Body.String())
	}
	waitJob(t, a)
	w := requestTest(a, "GET", "/api/job", "", c, csrf)
	if strings.Contains(w.Body.String(), "secret.invalid") || !strings.Contains(w.Body.String(), "DEVICE_OPERATION_FAILED") {
		t.Fatal("private output leaked")
	}
}
func TestJobMutualExclusionAndLogoutContinuation(t *testing.T) {
	a, f := testApp(t)
	f.wait = make(chan struct{})
	c, csrf := loginTest(t, a, "2007")
	if w := requestTest(a, "POST", "/api/action", `{"action":"install"}`, c, csrf); w.Code != 202 {
		t.Fatal("start")
	}
	if w := requestTest(a, "POST", "/api/action", `{"action":"enable"}`, c, csrf); w.Code != 409 {
		t.Fatal("no job exclusion")
	}
	requestTest(a, "POST", "/api/logout", `{}`, c, csrf)
	close(f.wait)
	waitJob(t, a)
	c, csrf = loginTest(t, a, "2007")
	w := requestTest(a, "GET", "/api/job", "", c, csrf)
	if !strings.Contains(w.Body.String(), `"state":"done"`) {
		t.Fatal("background job lost on logout")
	}
}
func TestBodyLimitAndNoTraversal(t *testing.T) {
	a, _ := testApp(t)
	if w := requestTest(a, "POST", "/api/login", `{"pin":"`+strings.Repeat("x", 3000)+`"}`, nil, ""); w.Code != 400 {
		t.Fatal("login body limit")
	}
	if w := requestTest(a, "GET", "/../../payload/u30/install.sh", "", nil, ""); w.Code < 400 {
		t.Fatal("payload exposed")
	}
	for _, p := range []string{"/", "/app.js", "/ui.js", "/flags.js", "/icon.png", "/sakura.webp"} {
		w := requestTest(a, "GET", p, "", nil, "")
		if w.Code != 200 || w.Header().Get("X-Frame-Options") != "DENY" || w.Header().Get("Content-Security-Policy") == "" {
			t.Fatalf("asset %s", p)
		}
		if p == "/app.js" && (strings.Contains(w.Body.String(), "runShellWithRoot") || strings.Contains(w.Body.String(), "admin.secret")) {
			t.Fatal("root transport in browser")
		}
	}
}
func TestTLSCertificateAndAtomicState(t *testing.T) {
	home := t.TempDir()
	cp, kp, e := certificate(home, "192.168.0.1:9088")
	if e != nil {
		t.Fatal(e)
	}
	before, _ := os.ReadFile(cp)
	again, _, e := certificate(home, "192.168.0.1:9088")
	if e != nil || again != cp {
		t.Fatal("tls reuse")
	}
	after, _ := os.ReadFile(cp)
	if string(before) != string(after) {
		t.Fatal("certificate regenerated")
	}
	if b, _ := os.ReadFile(kp); !strings.Contains(string(b), "PRIVATE KEY") {
		t.Fatal("key missing")
	}
	st, e := os.Stat(kp)
	if e != nil || st.Size() == 0 {
		t.Fatal("key empty")
	}
}
func TestShellArgumentsNeverInterpolated(t *testing.T) {
	var got []string
	d := androidDevice{invoke: func(_ context.Context, name string, args []string, _ string) (string, error) {
		if name != "bridge" {
			t.Fatal("wrong command")
		}
		got = append([]string{}, args...)
		return `{"ok":true}`, nil
	}}
	payload := `x'; touch /data/local/tmp/evil; #`
	_, e := d.Mutate(context.Background(), operation{Action: "select", Args: []string{"PROXY", payload}}, func(string) {})
	if e != nil || len(got) != 3 || got[0] != "select" || !strings.Contains(got[2], payload) {
		t.Fatal("argv transport failed")
	}
	if strings.Contains(got[1], ";") {
		t.Fatal("group not encoded")
	}
}
func TestEnableChecksGLOBALAndFailsClosed(t *testing.T) {
	var calls []string
	d := androidDevice{invoke: func(_ context.Context, name string, args []string, _ string) (string, error) {
		op := name
		if len(args) > 0 {
			op = args[0]
		}
		calls = append(calls, op)
		switch op {
		case "status":
			return "core=running\nsubscription=validated\ntransparent=off\ncontroller=authenticated-ready", nil
		case "repair":
			return "ok", nil
		case "proxies":
			return `{"proxies":{"GLOBAL":{"type":"Selector","all":["DIRECT"],"now":"DIRECT"},"DIRECT":{"type":"Direct"}}}`, nil
		case "providers":
			return `{"providers":{}}`, nil
		case "mode":
			return `{"mode":"global"}`, nil
		}
		return "", errors.New("UNEXPECTED")
	}}
	_, e := d.Mutate(context.Background(), operation{Action: "enable"}, func(string) {})
	if e == nil || e.Error() != "SELECT_NODE_FIRST" {
		t.Fatalf("wrong global preflight: %v", e)
	}
	for _, c := range calls {
		if c == "enable" {
			t.Fatal("capture enabled with DIRECT")
		}
	}
}
func TestImportInputNotCommandLine(t *testing.T) {
	const value = "https://example.invalid/subscribe/private-test-token"
	seen := false
	d := androidDevice{invoke: func(_ context.Context, name string, args []string, input string) (string, error) {
		if name == "bridge" && args[0] == "status" {
			return "core=running\nsubscription=validated\ntransparent=off", nil
		}
		if name == "update" {
			seen = true
			if len(args) != 1 || args[0] != "set" || input != value {
				t.Fatal("import not stdin")
			}
			return "committed", nil
		}
		return "", errors.New("UNEXPECTED")
	}}
	_, e := d.Mutate(context.Background(), operation{Action: "import_subscription", Value: value}, func(string) {})
	if e != nil || !seen {
		t.Fatal(e)
	}
}
