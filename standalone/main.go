package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

func prepare(home, variant string) error {
	if variant != "u30" && variant != "f50" {
		return errors.New("invalid_variant")
	}
	if e := privateDir(home); e != nil {
		return e
	}
	for _, dir := range []string{"state", "scripts", "offline", "tools"} {
		if e := privateDir(filepath.Join(home, dir)); e != nil {
			return e
		}
	}
	for _, pair := range [][2]string{{"payload/" + variant, "scripts"}, {"payload/assets", "offline"}, {"payload/tools", "tools"}} {
		entries, e := fs.ReadDir(files, pair[0])
		if e != nil {
			return e
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			body, e := files.ReadFile(pair[0] + "/" + entry.Name())
			if e != nil {
				return e
			}
			mode := fs.FileMode(0600)
			if pair[1] == "tools" || pair[1] == "scripts" {
				mode = 0700
			}
			if e = atomicFile(filepath.Join(home, pair[1], entry.Name()), body, mode); e != nil {
				return e
			}
		}
	}
	dest := filepath.Join(home, "state", "pin.json")
	if _, e := os.Lstat(dest); os.IsNotExist(e) {
		if p, e := readProfile("/data/adb/u30proxy/secret/global-ui-pin.json"); e != nil {
			return e
		} else if p != nil {
			if e = atomicFile(dest, []byte(mustJSON(p)), 0600); e != nil {
				return e
			}
		}
	}
	return atomicFile(filepath.Join(home, "variant"), []byte(variant), 0600)
}
func certificate(home, host string) (string, string, error) {
	certPath, keyPath := filepath.Join(home, "state", "tls.crt"), filepath.Join(home, "state", "tls.key")
	if _, e := os.Lstat(certPath); e == nil {
		if _, e = safeFile(certPath, 8192); e != nil {
			return "", "", e
		}
		if _, e = safeFile(keyPath, 8192); e != nil {
			return "", "", e
		}
		if _, e = tls.LoadX509KeyPair(certPath, keyPath); e != nil {
			return "", "", e
		}
		return certPath, keyPath, nil
	}
	key, e := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if e != nil {
		return "", "", e
	}
	serial, e := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if e != nil {
		return "", "", e
	}
	ip, _, _ := net.SplitHostPort(host)
	template := x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: "wu138di Global Tools"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().AddDate(1, 0, 0), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP(ip)}}
	der, e := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if e != nil {
		return "", "", e
	}
	kb, e := x509.MarshalPKCS8PrivateKey(key)
	if e != nil {
		return "", "", e
	}
	if e = atomicFile(keyPath, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: kb}), 0600); e != nil {
		return "", "", e
	}
	if e = atomicFile(certPath, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0600); e != nil {
		return "", "", e
	}
	return certPath, keyPath, nil
}
func main() {
	home := flag.String("home", "/data/adb/wu-global", "private installation directory")
	listen := flag.String("listen", "192.168.0.1:9088", "LAN address")
	variant := flag.String("variant", "u30", "u30 or f50")
	extract := flag.Bool("prepare", false, "extract verified offline payload")
	local := flag.Bool("local-check", false, "loopback-only UI/auth check without Android operations")
	flag.Parse()
	if *extract {
		if runtime.GOOS != "android" && runtime.GOOS != "linux" {
			log.Fatal("Android root required")
		}
		if os.Geteuid() != 0 {
			log.Fatal("Root required")
		}
		if e := prepare(*home, *variant); e != nil {
			log.Fatal("prepare failed: ", e)
		}
		fmt.Println("PREPARE_OK")
		return
	}
	ip, port, e := net.SplitHostPort(*listen)
	addr := net.ParseIP(ip)
	if e != nil || addr == nil || port == "" || (!addr.IsPrivate() && !addr.IsLoopback()) {
		log.Fatal("literal LAN/loopback listen address required")
	}
	var d device
	secure := true
	if *local {
		if !addr.IsLoopback() {
			log.Fatal("local-check requires loopback")
		}
		secure = false
		if e = privateDir(filepath.Join(*home, "state")); e != nil {
			log.Fatal(e)
		}
		d = offlineDevice{}
	} else {
		if (runtime.GOOS != "android" && runtime.GOOS != "linux") || os.Geteuid() != 0 {
			log.Fatal("Android Root required")
		}
		if b, e := safeFile(filepath.Join(*home, "variant"), 32); e == nil {
			*variant = strings.TrimSpace(string(b))
		}
		if *variant != "u30" && *variant != "f50" {
			log.Fatal("invalid variant")
		}
		d = &androidDevice{home: *home, variant: *variant}
	}
	a := newApp(d, *listen, filepath.Join(*home, "state", "pin.json"), secure)
	srv := &http.Server{Addr: *listen, Handler: a, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 90 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384, TLSConfig: &tls.Config{MinVersion: tls.VersionTLS12}, ErrorLog: log.New(os.Stderr, "http: ", 0)}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-signals
		a.shutdown()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	}()
	fmt.Printf("GLOBAL_MANAGER_READY %s\n", a.origin)
	if secure {
		cert, key, e := certificate(*home, *listen)
		if e != nil {
			log.Fatal("TLS initialization failed")
		}
		e = srv.ListenAndServeTLS(cert, key)
	} else {
		e = srv.ListenAndServe()
	}
	if e != nil && e != http.ErrServerClosed {
		log.Fatal("listen failed: ", e)
	}
}
