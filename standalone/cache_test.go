package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStoppedMetadataNeverInventsLiveTrafficOrDelay(t *testing.T) {
	home := t.TempDir()
	live := map[string]any{"mode": "rule", "proxies": map[string]any{"fixture": map[string]any{"name": "fixture", "type": "Hysteria2", "history": []any{map[string]any{"delay": 37}}, "server": "private-host", "password": "secret"}}, "rules": []any{}, "connections": map[string]any{"memory": 99, "connections": []any{"private-connection"}}}
	saveNodes(home, "hash-a", live)
	b, _ := os.ReadFile(filepath.Join(home, "state", "saved-nodes.json"))
	for _, s := range []string{"private-host", "secret", "private-connection", "history", "delay"} {
		if strings.Contains(string(b), s) {
			t.Fatal("private/stale runtime cache field: " + s)
		}
	}
	stopped := map[string]any{"status": map[string]string{"core": "stopped", "transparent": "off"}, "connections": map[string]any{"connections": []any{}, "memory": 0}}
	v := loadNodes(home, "hash-a", stopped)
	if v["cached"] != true || len(mapObject(v["proxies"])) != 1 || mapObject(v["connections"])["memory"] != 0 {
		t.Fatal("metadata not preserved truthfully")
	}
	other := loadNodes(home, "hash-b", map[string]any{})
	if other["cached"] == true {
		t.Fatal("stale metadata reused after provider changed")
	}
}
