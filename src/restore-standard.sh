#!/system/bin/sh
# Explicit standard-region-template restore; never replaces subscription/key/cache/custom files.
# --validate-only checks a private candidate without service or active configuration changes.
set -eu
umask 077
export LC_ALL=C
BASE=/data/adb/u30proxy
BB=/data/adb/magisk/busybox
MODE=${1:-restore}
case "$MODE" in restore|--validate-only) :;; *) printf '%s\n' 'Usage: restore-standard.sh [restore|--validate-only]' >&2; exit 2;; esac
fail() { printf 'U30_STANDARD_RULES_ERROR: %s\n' "$1" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail ROOT_REQUIRED
[ -x "$BB" ] && [ -x "$BASE/bin/mihomo" ] && [ -x "$BASE/control.sh" ] || fail COMPLETE_DEPLOYMENT_REQUIRED
for d in "$BASE" "$BASE/run" "$BASE/secret" "$BASE/mihomo" "$BASE/mihomo/rules" "$BASE/mihomo/providers"; do
    [ -d "$d" ] && [ ! -L "$d" ] || fail NON_SYMLINK_DEPLOYMENT_REQUIRED
done
for f in "$BASE/mihomo/config.yaml" "$BASE/secret/admin.secret" "$BASE/mihomo/providers/subscription.yaml" "$BASE/mihomo/rules/custom-direct.yaml" "$BASE/mihomo/rules/custom-proxy.yaml"; do
    [ -s "$f" ] && [ ! -L "$f" ] || fail PRIVATE_SOURCE_FILES_REQUIRED
done
for r in jp hk tw us sg kr; do
    [ ! -L "$BASE/mihomo/rules/region-$r.yaml" ] || fail REGION_SYMLINK_PRESERVED
done
KEY=$("$BB" cat "$BASE/secret/admin.secret")
case "$KEY" in ''|*[!A-Za-z0-9._~@-]*) fail PRIVATE_KEY_FORMAT_PRESERVED;; esac
[ "${#KEY}" -ge 16 ] && [ "${#KEY}" -le 256 ] || fail PRIVATE_KEY_LENGTH_PRESERVED
LOCK=$BASE/run/standard-rules.lock
"$BB" mkdir "$LOCK" 2>/dev/null || fail ANOTHER_STANDARD_RULES_ACTION_OR_STALE_LOCK
"$BB" chmod 700 "$LOCK"
printf '%s\n' "$$" > "$LOCK/pid"
X=
COMMITTING=0
cleanup() {
    rc=$?
    trap - EXIT HUP INT TERM
    if [ "$COMMITTING" = 1 ] && [ -n "$X" ] && [ -x "$X/rollback.sh" ]; then
        /system/bin/sh "$X/rollback.sh" > "$X/automatic-rollback.log" 2>&1 || {
            printf 'Preserved root-only recovery needs inspection: %s/rollback.sh\n' "$X" >&2
            rc=1
        }
    fi
    if [ -f "$LOCK/pid" ] && [ "$("$BB" cat "$LOCK/pid")" = "$$" ]; then
        "$BB" rm -f "$LOCK/pid"
        "$BB" rmdir "$LOCK" || :
    fi
    KEY=
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
X=$BASE/secret/standard-rules-$("$BB" date +%Y%m%dT%H%M%S)-$$
"$BB" mkdir "$X"
"$BB" chmod 700 "$X"
"$BB" cp "$BASE/mihomo/config.yaml" "$X/config.original.yaml"
for r in jp hk tw us sg kr; do
    if [ -f "$BASE/mihomo/rules/region-$r.yaml" ]; then
        "$BB" cp "$BASE/mihomo/rules/region-$r.yaml" "$X/region-$r.original.yaml"
    fi
done
"$BB" chmod 600 "$X"/*
"$BB" cp -R "$BASE/mihomo" "$X/candidate-home"
"$BB" chmod 700 "$X/candidate-home" "$X/candidate-home/rules" "$X/candidate-home/providers"
cat > "$X/config.public.template.yaml" <<'U30_PUBLIC_CONFIG_TEMPLATE_YAML_EOF'
mixed-port: 7890
tproxy-port: 7893
allow-lan: true
bind-address: '*'
mode: rule
log-level: warning
ipv6: true
find-process-mode: off
interface-name: sipa_eth0
external-controller: 192.168.0.1:9090
secret: '@API_SECRET@'
external-ui: ui
profile:
  store-selected: true
  store-fake-ip: false
dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: true
  enhanced-mode: redir-host
  respect-rules: true
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  proxy-server-nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  nameserver:
    - https://1.1.1.1/dns-query#PROXY
    - https://8.8.8.8/dns-query#PROXY
  nameserver-policy:
    'rule-set:custom-direct':
      - https://dns.alidns.com/dns-query
      - https://doh.pub/dns-query
    'rule-set:geosite-private':
      - 223.5.5.5
      - 119.29.29.29
    'rule-set:region-jp':
      - https://1.1.1.1/dns-query#REGION-JP
      - https://8.8.8.8/dns-query#REGION-JP
    'rule-set:region-hk':
      - https://1.1.1.1/dns-query#REGION-HK
      - https://8.8.8.8/dns-query#REGION-HK
    'rule-set:region-tw':
      - https://1.1.1.1/dns-query#REGION-TW
      - https://8.8.8.8/dns-query#REGION-TW
      # Current TW exits reach BAHA but time out on public DoH. DNS-only
      # fallback retains REGION-TW for the actual application's traffic.
      - https://1.1.1.1/dns-query#PROXY
      - https://8.8.8.8/dns-query#PROXY
    'rule-set:region-us':
      - https://1.1.1.1/dns-query#REGION-US
      - https://8.8.8.8/dns-query#REGION-US
    'rule-set:region-sg':
      - https://1.1.1.1/dns-query#REGION-SG
      - https://8.8.8.8/dns-query#REGION-SG
    'rule-set:region-kr':
      - https://1.1.1.1/dns-query#REGION-KR
      - https://8.8.8.8/dns-query#REGION-KR
    'rule-set:geosite-cn':
      - https://dns.alidns.com/dns-query
      - https://doh.pub/dns-query
sniffer:
  enable: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
proxy-providers:
  subscription:
    type: file
    path: ./providers/subscription.yaml
    health-check:
      enable: true
      interval: 180
      url: https://www.gstatic.com/generate_204
      expected-status: 204
proxy-groups:
  - name: PROXY
    type: select
    proxies: [AUTO, DIRECT]
    use: [subscription]
  - name: AUTO
    type: url-test
    use: [subscription]
    url: https://www.gstatic.com/generate_204
    interval: 600
    tolerance: 100
  - name: REGION-JP
    type: fallback
    use: [subscription]
    filter: '(?i)(日本|东京|東京|大阪|名古屋|🇯🇵|japan|tokyo|osaka|nagoya|(?:^|[^a-z])jp(?:$|[^a-z]))'
    empty-fallback: REJECT
    url: https://www.gstatic.com/generate_204
    expected-status: 204
    interval: 180
    timeout: 5000
    max-failed-times: 1
  - name: REGION-HK
    type: fallback
    use: [subscription]
    filter: '(?i)(香港|🇭🇰|hong[ -]*kong|(?:^|[^a-z])hk(?:$|[^a-z]))'
    empty-fallback: REJECT
    url: https://www.gstatic.com/generate_204
    expected-status: 204
    interval: 180
    timeout: 5000
    max-failed-times: 1
  - name: REGION-TW
    type: fallback
    use: [subscription]
    filter: '(?i)(台湾|台灣|臺灣|台北|臺北|🇹🇼|taiwan|taipei|(?:^|[^a-z])tw(?:$|[^a-z]))'
    empty-fallback: REJECT
    url: https://www.gstatic.com/generate_204
    expected-status: 204
    interval: 180
    timeout: 5000
    max-failed-times: 1
  - name: REGION-US
    type: fallback
    use: [subscription]
    filter: '(?i)(美国|美國|洛杉矶|洛杉磯|纽约|紐約|旧金山|舊金山|西雅图|西雅圖|🇺🇸|united[ -]*states|los[ -]*angeles|new[ -]*york|san[ -]*francisco|seattle|(?:^|[^a-z])(?:us|usa)(?:$|[^a-z]))'
    empty-fallback: REJECT
    url: https://www.gstatic.com/generate_204
    expected-status: 204
    interval: 180
    timeout: 5000
    max-failed-times: 1
  - name: REGION-SG
    type: fallback
    use: [subscription]
    filter: '(?i)(新加坡|狮城|獅城|🇸🇬|singapore|(?:^|[^a-z])sg(?:$|[^a-z]))'
    empty-fallback: REJECT
    url: https://www.gstatic.com/generate_204
    expected-status: 204
    interval: 180
    timeout: 5000
    max-failed-times: 1
  - name: REGION-KR
    type: fallback
    use: [subscription]
    filter: '(?i)(韩国|韓國|首尔|首爾|🇰🇷|(?:south[ -]*)?korea|seoul|(?:^|[^a-z])kr(?:$|[^a-z]))'
    empty-fallback: REJECT
    url: https://www.gstatic.com/generate_204
    expected-status: 204
    interval: 180
    timeout: 5000
    max-failed-times: 1
rule-providers:
  custom-proxy:
    type: file
    behavior: classical
    path: ./rules/custom-proxy.yaml
  custom-direct:
    type: file
    behavior: classical
    path: ./rules/custom-direct.yaml
  region-jp:
    type: file
    behavior: domain
    path: ./rules/region-jp.yaml
  region-hk:
    type: file
    behavior: domain
    path: ./rules/region-hk.yaml
  region-tw:
    type: file
    behavior: domain
    path: ./rules/region-tw.yaml
  region-us:
    type: file
    behavior: domain
    path: ./rules/region-us.yaml
  region-sg:
    type: file
    behavior: domain
    path: ./rules/region-sg.yaml
  region-kr:
    type: file
    behavior: domain
    path: ./rules/region-kr.yaml
  geosite-private:
    type: file
    behavior: domain
    format: mrs
    path: ./rules/geosite-private.mrs
  geoip-private:
    type: file
    behavior: ipcidr
    format: mrs
    path: ./rules/geoip-private.mrs
  geosite-cn:
    type: file
    behavior: domain
    format: mrs
    path: ./rules/geosite-cn.mrs
  geoip-cn:
    type: file
    behavior: ipcidr
    format: mrs
    path: ./rules/geoip-cn.mrs
rules:
  - RULE-SET,custom-proxy,PROXY
  - RULE-SET,custom-direct,DIRECT
  - RULE-SET,geosite-private,DIRECT
  - RULE-SET,geoip-private,DIRECT,no-resolve
  - RULE-SET,region-jp,REGION-JP
  - RULE-SET,region-hk,REGION-HK
  - RULE-SET,region-tw,REGION-TW
  - RULE-SET,region-us,REGION-US
  - RULE-SET,region-sg,REGION-SG
  - RULE-SET,region-kr,REGION-KR
  - RULE-SET,geosite-cn,DIRECT
  - RULE-SET,geoip-cn,DIRECT,no-resolve
  - MATCH,PROXY
U30_PUBLIC_CONFIG_TEMPLATE_YAML_EOF
cat > "$X/candidate-home/rules/region-jp.yaml" <<'U30_PUBLIC_REGION_JP_YAML_EOF'
# ABEMA / NHK ONE: platform-owned domains and dedicated CDN hosts.
payload:
  - '+.abema.tv'
  - '+.abema.io'
  - '+.abema-tv.com'
  - 'abematv.akamaized.net'
  - 'ds-linear-abematv.akamaized.net'
  - 'ds-vod-abematv.akamaized.net'
  - 'linear-abematv.akamaized.net'
  - 'vod-abematv.akamaized.net'
  - '+.web.nhk'
  - 'one.nhk'
  - '+.ac1.nhk'
  - '+.ac2.nhk'
  - '+.bx.nhk'
  - '+.nhk.jp'
  - '+.nhk.or.jp'
  - 'api-local.ss.org.nhk'
U30_PUBLIC_REGION_JP_YAML_EOF
cat > "$X/candidate-home/rules/region-hk.yaml" <<'U30_PUBLIC_REGION_HK_YAML_EOF'
# TVB News: platform-owned domains, not shared CDN suffixes.
payload:
  - '+.tvb.com'
U30_PUBLIC_REGION_HK_YAML_EOF
cat > "$X/candidate-home/rules/region-tw.yaml" <<'U30_PUBLIC_REGION_TW_YAML_EOF'
# Bahamut Anime: Taiwan; dedicated CDN hosts only.
payload:
  - '+.gamer.com.tw'
  - '+.bahamut.com.tw'
  - 'bahamut.akamaized.net'
  - 'gamer-cds.cdn.hinet.net'
  - 'gamer2-cds.cdn.hinet.net'
U30_PUBLIC_REGION_TW_YAML_EOF
cat > "$X/candidate-home/rules/region-us.yaml" <<'U30_PUBLIC_REGION_US_YAML_EOF'
payload: []
U30_PUBLIC_REGION_US_YAML_EOF
cat > "$X/candidate-home/rules/region-sg.yaml" <<'U30_PUBLIC_REGION_SG_YAML_EOF'
payload: []
U30_PUBLIC_REGION_SG_YAML_EOF
cat > "$X/candidate-home/rules/region-kr.yaml" <<'U30_PUBLIC_REGION_KR_YAML_EOF'
payload: []
U30_PUBLIC_REGION_KR_YAML_EOF

"$BB" sed "s/@API_SECRET@/$KEY/" "$X/config.public.template.yaml" > "$X/candidate-home/config.yaml"
KEY=
"$BB" find "$X/candidate-home" -type f -exec chmod 600 {} \;
"$BASE/bin/mihomo" -t -d "$X/candidate-home" > "$X/candidate-validation.log" 2>&1 || fail CANDIDATE_INVALID_ORIGINALS_PRESERVED
"$BB" chmod 600 "$X/candidate-validation.log"
cat > "$X/rollback.sh" <<'U30_STANDARD_ROLLBACK_EOF'
#!/system/bin/sh
set -eu
umask 077
[ "$(id -u)" = 0 ] || exit 1
BASE=/data/adb/u30proxy
BB=/data/adb/magisk/busybox
X=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$X" in /data/adb/u30proxy/secret/standard-rules-*) :;; *) exit 1;; esac
[ -f "$X/config.original.yaml" ] && [ ! -L "$X/config.original.yaml" ] || exit 1
/system/bin/sh "$BASE/control.sh" stop
"$BB" cp "$X/config.original.yaml" "$BASE/mihomo/config.yaml.standard-rollback.tmp"
"$BB" chmod 600 "$BASE/mihomo/config.yaml.standard-rollback.tmp"
"$BB" mv -f "$BASE/mihomo/config.yaml.standard-rollback.tmp" "$BASE/mihomo/config.yaml"
for r in jp hk tw us sg kr; do
    if [ -f "$X/region-$r.original.yaml" ]; then
        "$BB" cp "$X/region-$r.original.yaml" "$BASE/mihomo/rules/region-$r.yaml.standard-rollback.tmp"
        "$BB" chmod 600 "$BASE/mihomo/rules/region-$r.yaml.standard-rollback.tmp"
        "$BB" mv -f "$BASE/mihomo/rules/region-$r.yaml.standard-rollback.tmp" "$BASE/mihomo/rules/region-$r.yaml"
    else
        "$BB" rm -f "$BASE/mihomo/rules/region-$r.yaml"
    fi
done
/system/bin/sh "$BASE/control.sh" start
/system/bin/sh "$BASE/control.sh" status
U30_STANDARD_ROLLBACK_EOF
"$BB" chmod 700 "$X/rollback.sh"
/system/bin/sh -n "$X/rollback.sh" || fail ROLLBACK_SYNTAX_FAILED
if [ "$MODE" = --validate-only ]; then
    printf 'U30_STANDARD_RULES_OK: candidate validated; services and active configuration untouched.\nPrivate candidate: %s\n' "$X"
    exit 0
fi
COMMITTING=1
/system/bin/sh "$BASE/control.sh" stop > "$X/stop.log" 2>&1 || fail STOP_FAILED
"$BB" cp "$X/candidate-home/config.yaml" "$BASE/mihomo/config.yaml.standard.tmp"
"$BB" chmod 600 "$BASE/mihomo/config.yaml.standard.tmp"
"$BB" mv -f "$BASE/mihomo/config.yaml.standard.tmp" "$BASE/mihomo/config.yaml"
for r in jp hk tw us sg kr; do
    "$BB" cp "$X/candidate-home/rules/region-$r.yaml" "$BASE/mihomo/rules/region-$r.yaml.standard.tmp"
    "$BB" chmod 600 "$BASE/mihomo/rules/region-$r.yaml.standard.tmp"
    "$BB" mv -f "$BASE/mihomo/rules/region-$r.yaml.standard.tmp" "$BASE/mihomo/rules/region-$r.yaml"
done
/system/bin/sh "$BASE/control.sh" start > "$X/start.log" 2>&1 || fail START_FAILED_ROLLING_BACK
/system/bin/sh "$BASE/control.sh" status > "$X/status.txt"
for state in core=running controller=authenticated-ready admin=running watchdog=running; do
    "$BB" grep -F -x "$state" "$X/status.txt" >/dev/null || fail SERVICE_NOT_READY_ROLLING_BACK
done
printf '%s\n' "$X" > "$BASE/secret/standard-rules-latest.tmp.$$"
"$BB" chmod 600 "$BASE/secret/standard-rules-latest.tmp.$$"
"$BB" mv -f "$BASE/secret/standard-rules-latest.tmp.$$" "$BASE/secret/standard-rules-latest"
COMMITTING=0
"$BB" cat "$X/status.txt"
printf 'U30_STANDARD_RULES_OK: public template restored; subscription/key/cache/custom files preserved.\nRoot-only rollback: /system/bin/sh %s/rollback.sh\n' "$X"
