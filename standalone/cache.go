package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"path/filepath"
)

type savedNodes struct {
	Provider string         `json:"provider_sha256"`
	Mode     any            `json:"mode"`
	Proxies  map[string]any `json:"proxies"`
	Rules    any            `json:"rules"`
}

func providerHash() string {
	body, e := safeFile("/data/adb/u30proxy/mihomo/providers/subscription.yaml", 8*1024*1024)
	if e != nil {
		return ""
	}
	sum := sha256.Sum256(body)
	return hex.EncodeToString(sum[:])
}
func saveNodes(home, provider string, value map[string]any) {
	if home == "" || provider == "" {
		return
	}
	nodes := map[string]any{}
	for name, n := range mapObject(value["proxies"]) {
		v := mapObject(n)
		copy := map[string]any{}
		for _, key := range []string{"name", "type", "all", "now", "udp"} {
			if x, ok := v[key]; ok {
				copy[key] = x
			}
		}
		nodes[name] = copy
	}
	body, e := json.Marshal(savedNodes{provider, value["mode"], nodes, value["rules"]})
	if e == nil && len(body) <= 4*1024*1024 {
		_ = atomicFile(filepath.Join(home, "state", "saved-nodes.json"), body, 0600)
	}
}
func loadNodes(home, provider string, value map[string]any) map[string]any {
	if home == "" || provider == "" {
		return value
	}
	body, e := safeFile(filepath.Join(home, "state", "saved-nodes.json"), 4*1024*1024)
	if e != nil {
		return value
	}
	var saved savedNodes
	if json.Unmarshal(body, &saved) != nil || saved.Provider != provider {
		return value
	}
	value["mode"], value["proxies"], value["rules"], value["cached"] = saved.Mode, saved.Proxies, saved.Rules, true
	return value
}
