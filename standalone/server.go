package main

import (
	"context"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// The build creates these files from the existing, reviewed plugin sources.
// No browser receives a shell transport or the Mihomo controller credential.
//
//go:embed web/* payload/*/*
var files embed.FS

type device interface {
	Read(context.Context, string, []string) (any, error)
	Mutate(context.Context, operation, func(string)) (any, error)
}
type operation struct {
	Action string   `json:"action"`
	Args   []string `json:"args,omitempty"`
	Value  string   `json:"value,omitempty"`
}
type pinProfile struct {
	V          int    `json:"v"`
	Salt       string `json:"salt"`
	Iterations int    `json:"iterations"`
	Hash       string `json:"hash"`
}
type session struct {
	CSRF    string
	Expires time.Time
}
type attempts struct {
	Count int
	Until time.Time
}
type job struct {
	ID     string `json:"id"`
	State  string `json:"state"`
	Stage  string `json:"stage"`
	Result any    `json:"result,omitempty"`
	Code   string `json:"code,omitempty"`
}
type app struct {
	dev                   device
	host, origin, pinPath string
	secure                bool
	mu                    sync.Mutex
	authMu                sync.Mutex
	sessions              map[string]session
	failures              map[string]attempts
	loginWindow           time.Time
	loginCount            int
	current               *job
	jobCancel             context.CancelFunc
}

func newApp(d device, host, pinPath string, secure bool) *app {
	scheme := "http"
	if secure {
		scheme = "https"
	}
	return &app{dev: d, host: host, origin: scheme + "://" + host, pinPath: pinPath, secure: secure, sessions: map[string]session{}, failures: map[string]attempts{}}
}
func token() string {
	b := make([]byte, 32)
	if _, e := rand.Read(b); e != nil {
		panic("random source unavailable")
	}
	return hex.EncodeToString(b)
}
func safeFile(path string, limit int64) ([]byte, error) {
	info, e := os.Lstat(path)
	if e != nil {
		return nil, e
	}
	if !info.Mode().IsRegular() || info.Size() > limit {
		return nil, errors.New("invalid_private_file")
	}
	return os.ReadFile(path)
}
func privateDir(path string) error {
	// Reject symlinks in the entire path, not just its final component.
	path = filepath.Clean(path)
	var parts []string
	for p := path; ; p = filepath.Dir(p) {
		parts = append(parts, p)
		if filepath.Dir(p) == p {
			break
		}
	}
	for i := len(parts) - 1; i >= 0; i-- {
		p := parts[i]
		st, e := os.Lstat(p)
		if os.IsNotExist(e) {
			if e = os.Mkdir(p, 0700); e != nil {
				return e
			}
			continue
		}
		if e != nil {
			return e
		}
		if !st.IsDir() || st.Mode()&os.ModeSymlink != 0 {
			return errors.New("invalid_private_directory")
		}
	}
	return nil
}
func atomicFile(path string, body []byte, mode fs.FileMode) error {
	if e := privateDir(filepath.Dir(path)); e != nil {
		return e
	}
	if st, e := os.Lstat(path); e == nil && (!st.Mode().IsRegular() || st.Mode()&os.ModeSymlink != 0) {
		return errors.New("invalid_destination")
	}
	f, e := os.CreateTemp(filepath.Dir(path), ".new-*")
	if e != nil {
		return e
	}
	name := f.Name()
	defer os.Remove(name)
	if e = f.Chmod(mode); e == nil {
		_, e = f.Write(body)
	}
	if e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e == nil {
		e = ce
	}
	if e != nil {
		return e
	}
	return os.Rename(name, path)
}
func readProfile(path string) (*pinProfile, error) {
	body, e := safeFile(path, 2048)
	if os.IsNotExist(e) {
		return nil, nil
	}
	if e != nil {
		return nil, e
	}
	var p pinProfile
	if json.Unmarshal(body, &p) != nil || p.V != 1 || p.Iterations != 100000 || len(p.Salt) != 32 || len(p.Hash) != 64 {
		return nil, errors.New("pin_profile_invalid")
	}
	if _, e = hex.DecodeString(p.Salt); e != nil {
		return nil, e
	}
	if _, e = hex.DecodeString(p.Hash); e != nil {
		return nil, e
	}
	return &p, nil
}
func validPIN(pin string) bool {
	return utf8.ValidString(pin) && utf8.RuneCountInString(pin) >= 4 && utf8.RuneCountInString(pin) <= 64 && !strings.ContainsFunc(pin, func(r rune) bool { return r < 32 || r == 127 })
}
func matchesPIN(pin string, p *pinProfile) bool {
	if !validPIN(pin) {
		return false
	}
	if p == nil {
		return subtle.ConstantTimeCompare([]byte(pin), []byte("2007")) == 1
	}
	salt, _ := hex.DecodeString(p.Salt)
	want, _ := hex.DecodeString(p.Hash)
	got, e := pbkdf2.Key(sha256.New, pin, salt, p.Iterations, 32)
	return e == nil && subtle.ConstantTimeCompare(got, want) == 1
}
func makeProfile(pin string) *pinProfile {
	salt := make([]byte, 16)
	if _, e := rand.Read(salt); e != nil {
		panic("random source unavailable")
	}
	hash, e := pbkdf2.Key(sha256.New, pin, salt, 100000, 32)
	if e != nil {
		panic(e)
	}
	return &pinProfile{1, hex.EncodeToString(salt), 100000, hex.EncodeToString(hash)}
}
func send(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func apiError(w http.ResponseWriter, status int, code string) {
	send(w, status, map[string]any{"ok": false, "code": code})
}
func decode(w http.ResponseWriter, r *http.Request, out any, limit int64) bool {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		apiError(w, 415, "JSON_REQUIRED")
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if e := d.Decode(out); e != nil {
		apiError(w, 400, "INVALID_BODY")
		return false
	}
	if d.Decode(&struct{}{}) != io.EOF {
		apiError(w, 400, "INVALID_BODY")
		return false
	}
	return true
}
func (a *app) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h := w.Header()
	h.Set("Cache-Control", "no-store")
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("X-Frame-Options", "DENY")
	h.Set("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; font-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
	ip, _, e := net.SplitHostPort(r.RemoteAddr)
	peer := net.ParseIP(ip)
	if e != nil || peer == nil || (!peer.IsLoopback() && !peer.IsPrivate()) {
		apiError(w, 403, "LAN_ONLY")
		return
	}
	if r.Host != a.host {
		apiError(w, 403, "HOST_REJECTED")
		return
	}
	if r.Method != "GET" && r.Method != "POST" {
		apiError(w, 405, "METHOD_REJECTED")
		return
	}
	if o := r.Header.Get("Origin"); o != "" && o != a.origin {
		apiError(w, 403, "ORIGIN_REJECTED")
		return
	}
	if r.Method == "POST" && r.Header.Get("Origin") != a.origin {
		apiError(w, 403, "ORIGIN_REQUIRED")
		return
	}
	switch r.URL.Path {
	case "/api/pin/status":
		if r.Method != "GET" {
			apiError(w, 405, "METHOD_REJECTED")
			return
		}
		a.authMu.Lock()
		p, e := readProfile(a.pinPath)
		a.authMu.Unlock()
		if e != nil {
			apiError(w, 503, "PIN_STORAGE_INVALID")
			return
		}
		send(w, 200, map[string]any{"configured": p != nil})
		return
	case "/api/login":
		a.login(w, r, ip)
		return
	case "/", "/app.js", "/app.css", "/ui.js", "/flags.js", "/icon.png", "/sakura.webp":
		if r.Method != "GET" {
			apiError(w, 405, "METHOD_REJECTED")
			return
		}
		name := strings.TrimPrefix(r.URL.Path, "/")
		if name == "" {
			name = "index.html"
		}
		b, e := files.ReadFile("web/" + name)
		if e != nil {
			http.NotFound(w, r)
			return
		}
		types := map[string]string{".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".png": "image/png", ".webp": "image/webp"}
		h.Set("Content-Type", types[filepath.Ext(name)])
		_, _ = w.Write(b)
		return
	}
	sid, s, ok := a.authenticate(r)
	if !ok {
		apiError(w, 401, "LOGIN_REQUIRED")
		return
	}
	if r.Method == "POST" && subtle.ConstantTimeCompare([]byte(r.Header.Get("X-CSRF-Token")), []byte(s.CSRF)) != 1 {
		apiError(w, 403, "CSRF_REJECTED")
		return
	}
	switch r.URL.Path {
	case "/api/logout":
		if r.Method != "POST" {
			apiError(w, 405, "METHOD_REJECTED")
			return
		}
		a.mu.Lock()
		delete(a.sessions, sid)
		a.mu.Unlock()
		a.cookie(w, "", -1)
		send(w, 200, map[string]bool{"ok": true})
	case "/api/pin/change":
		a.changePIN(w, r)
	case "/api/read":
		if r.Method != "POST" {
			apiError(w, 405, "METHOD_REJECTED")
			return
		}
		var q operation
		if !decode(w, r, &q, 16384) {
			return
		}
		if !validRead(q) {
			apiError(w, 400, "OPERATION_REJECTED")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
		defer cancel()
		v, e := a.dev.Read(ctx, q.Action, q.Args)
		if e != nil {
			apiError(w, 502, safeCode(e))
			return
		}
		send(w, 200, v)
	case "/api/action":
		a.startJob(w, r)
	case "/api/job":
		if r.Method != "GET" {
			apiError(w, 405, "METHOD_REJECTED")
			return
		}
		a.mu.Lock()
		defer a.mu.Unlock()
		if a.current == nil {
			send(w, 200, map[string]any{"state": "idle"})
			return
		}
		send(w, 200, a.current)
	default:
		apiError(w, 404, "NOT_FOUND")
	}
}
func (a *app) cookie(w http.ResponseWriter, value string, age int) {
	http.SetCookie(w, &http.Cookie{Name: "wu_global_session", Value: value, Path: "/", HttpOnly: true, Secure: a.secure, SameSite: http.SameSiteStrictMode, MaxAge: age})
}
func (a *app) authenticate(r *http.Request) (string, session, bool) {
	c, e := r.Cookie("wu_global_session")
	if e != nil {
		return "", session{}, false
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	s, ok := a.sessions[c.Value]
	if !ok || time.Now().After(s.Expires) {
		delete(a.sessions, c.Value)
		return "", session{}, false
	}
	return c.Value, s, true
}
func (a *app) login(w http.ResponseWriter, r *http.Request, ip string) {
	if r.Method != "POST" {
		apiError(w, 405, "METHOD_REJECTED")
		return
	}
	var q struct {
		PIN string `json:"pin"`
	}
	if !decode(w, r, &q, 1024) {
		return
	}
	now := time.Now()
	a.mu.Lock()
	f := a.failures[ip]
	if now.After(a.loginWindow) {
		a.loginCount = 0
		a.loginWindow = now.Add(time.Minute)
	}
	if (f.Count >= 5 && now.Before(f.Until)) || a.loginCount >= 20 {
		a.mu.Unlock()
		w.Header().Set("Retry-After", "60")
		apiError(w, 429, "LOGIN_RATE_LIMIT")
		return
	}
	a.loginCount++
	a.mu.Unlock()
	a.authMu.Lock()
	defer a.authMu.Unlock()
	p, e := readProfile(a.pinPath)
	ok := e == nil && matchesPIN(q.PIN, p)
	q.PIN = ""
	if e != nil {
		apiError(w, 503, "PIN_STORAGE_INVALID")
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if !ok {
		f = a.failures[ip]
		if now.After(f.Until) {
			f = attempts{Until: now.Add(time.Minute)}
		}
		f.Count++
		if len(a.failures) < 128 {
			a.failures[ip] = f
		}
		apiError(w, 401, "PIN_WRONG")
		return
	}
	delete(a.failures, ip)
	for id, s := range a.sessions {
		if now.After(s.Expires) {
			delete(a.sessions, id)
		}
	}
	if len(a.sessions) >= 16 {
		apiError(w, 429, "SESSION_LIMIT")
		return
	}
	sid, csrf := token(), token()
	a.sessions[sid] = session{csrf, now.Add(8 * time.Hour)}
	a.cookie(w, sid, 28800)
	send(w, 200, map[string]any{"ok": true, "csrf": csrf})
}
func (a *app) changePIN(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		apiError(w, 405, "METHOD_REJECTED")
		return
	}
	var q struct {
		Current string `json:"current"`
		Next    string `json:"next"`
		Confirm string `json:"confirm"`
	}
	if !decode(w, r, &q, 2048) {
		return
	}
	if !validPIN(q.Next) {
		apiError(w, 400, "PIN_LENGTH")
		return
	}
	if q.Next != q.Confirm {
		apiError(w, 400, "PIN_CONFIRM")
		return
	}
	if q.Next == q.Current {
		apiError(w, 400, "PIN_SAME")
		return
	}
	a.authMu.Lock()
	defer a.authMu.Unlock()
	p, e := readProfile(a.pinPath)
	if e != nil {
		apiError(w, 503, "PIN_STORAGE_INVALID")
		return
	}
	if !matchesPIN(q.Current, p) {
		apiError(w, 403, "PIN_CURRENT_WRONG")
		return
	}
	body, _ := json.Marshal(makeProfile(q.Next))
	if e = atomicFile(a.pinPath, body, 0600); e != nil {
		apiError(w, 500, "PIN_SAVE_FAILED")
		return
	}
	a.mu.Lock()
	a.sessions = map[string]session{}
	a.mu.Unlock()
	a.cookie(w, "", -1)
	send(w, 200, map[string]bool{"ok": true, "configured": true})
}
func validText(s string, limit int) bool {
	return utf8.ValidString(s) && len(s) > 0 && len(s) <= limit && !strings.ContainsFunc(s, func(r rune) bool { return r < 32 || r == 127 })
}
func validRead(q operation) bool {
	if q.Value != "" {
		return false
	}
	switch q.Action {
	case "snapshot", "status", "proxies", "rules", "connections", "diagnostics":
		return len(q.Args) == 0
	case "delay":
		return len(q.Args) == 1 && validText(q.Args[0], 1024)
	}
	return false
}
func validOperation(q operation) bool {
	switch q.Action {
	case "install", "refresh", "standard", "rollback_rules":
		return len(q.Args) == 0 && q.Value == ""
	case "start", "enable", "disable", "restart", "stop":
		return len(q.Args) == 0 && q.Value == ""
	case "autostart":
		return len(q.Args) == 1 && (q.Args[0] == "yes" || q.Args[0] == "no") && q.Value == ""
	case "set_mode":
		return len(q.Args) == 1 && (q.Args[0] == "rule" || q.Args[0] == "global" || q.Args[0] == "direct") && q.Value == ""
	case "select":
		return len(q.Args) == 2 && validText(q.Args[0], 1024) && validText(q.Args[1], 1024) && q.Value == ""
	case "close_connection":
		return len(q.Args) == 1 && validText(q.Args[0], 128) && q.Value == ""
	case "import_yaml":
		return len(q.Args) == 0 && len(q.Value) > 0 && len(q.Value) <= 1048576 && utf8.ValidString(q.Value)
	case "import_subscription":
		return len(q.Args) == 0 && validSubscription(q.Value)
	}
	return false
}
func safeCode(e error) string {
	code := e.Error()
	if len(code) > 96 {
		return "DEVICE_OPERATION_FAILED"
	}
	for _, c := range code {
		if !(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_') {
			return "DEVICE_OPERATION_FAILED"
		}
	}
	return code
}
func (a *app) startJob(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		apiError(w, 405, "METHOD_REJECTED")
		return
	}
	var q operation
	if !decode(w, r, &q, 2*1024*1024) {
		return
	}
	if !validOperation(q) {
		apiError(w, 400, "OPERATION_REJECTED")
		return
	}
	a.mu.Lock()
	if a.current != nil && a.current.State == "running" {
		a.mu.Unlock()
		apiError(w, 409, "JOB_BUSY")
		return
	}
	j := &job{ID: token(), State: "running", Stage: "准备"}
	a.current = j
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
	a.jobCancel = cancel
	a.mu.Unlock()
	go func() {
		defer cancel()
		v, e := a.dev.Mutate(ctx, q, func(stage string) { a.mu.Lock(); j.Stage = stage; a.mu.Unlock() })
		q.Value = ""
		a.mu.Lock()
		defer a.mu.Unlock()
		j.Stage = ""
		if e != nil {
			j.State = "failed"
			j.Code = safeCode(e)
		} else {
			j.State = "done"
			j.Result = v
		}
	}()
	send(w, 202, map[string]any{"id": j.ID, "state": "running"})
}
func (a *app) shutdown() {
	a.mu.Lock()
	if a.jobCancel != nil {
		a.jobCancel()
	}
	a.mu.Unlock()
}
func mustJSON(v any) string { b, _ := json.Marshal(v); return string(b) }

var _ = fmt.Sprintf
