#!/system/bin/sh
# Network-only repair. Keeps subscription, controller, rules, selections cache and capture state.
set -eu
umask 077
B=/data/adb/u30proxy
BB=
for P in /data/adb/u30proxy-tools/busybox /data/adb/magisk/busybox; do [ ! -x "$P" ] || { BB=$P; break; }; done
[ -n "$BB" ] || exit 69
CURL=
for P in /system/bin/curl /data/data/com.minikano.f50_sms/files/curl; do [ ! -x "$P" ] || { CURL=$P; break; }; done
[ -n "$CURL" ] || exit 69
fail(){ printf 'U30_PLUGIN_ERROR: %s\n' "$1" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail ROOT_REQUIRED
[ -x "$B/control.sh" ] && [ -x "$B/bin/mihomo" ] || fail DEPLOYMENT_REQUIRED
[ ! -f "$B/run/enabled" ] || fail STOP_PROXY_BEFORE_NETWORK_REPAIR
C=$B/mihomo/config.yaml
[ -f "$C" ] && [ ! -L "$C" ] && [ -d "$B/secret" ] && [ ! -L "$B/secret" ] || fail CONFIG_LAYOUT_REQUIRED
W=$(ip -4 route get 223.5.5.5 | "$BB" awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1);exit}')
case "$W" in ''|*[!A-Za-z0-9_.-]*|lo|br0|dummy*) fail WAN_ROUTE_UNCONFIRMED;; esac
ip -4 -o addr show dev "$W" | "$BB" grep -q ' inet ' || fail WAN_IPV4_REQUIRED
[ "$("$BB" grep -c '^interface-name:' "$C")" = 1 ] || fail INTERFACE_FIELD_UNCONFIRMED
[ "$("$BB" grep -c '^  proxy-server-nameserver:' "$C")" = 1 ] || fail BOOTSTRAP_DNS_FIELD_UNCONFIRMED
D=$B/secret/network-repair-$("$BB" date +%Y%m%dT%H%M%S)-$$
"$BB" mkdir "$D";"$BB" chmod 700 "$D"
"$BB" cp -p "$C" "$D/original.yaml"
"$BB" sha256sum "$C" > "$D/baseline.sha256"
"$BB" awk -v wan="$W" '
/^interface-name:/ { print "interface-name: " wan; next }
/^  proxy-server-nameserver:/ { print; print "    - udp://223.5.5.5:53#DIRECT"; print "    - udp://119.29.29.29:53#DIRECT"; skip=1; next }
skip && /^  (  |- )/ {next}
skip {skip=0}
{print}
' "$C" > "$D/candidate.yaml"
"$BB" chmod 600 "$D"/*
A=$("$BB" sha256sum "$C");N=$("$BB" sha256sum "$D/candidate.yaml")
if [ "${A%% *}" = "${N%% *}" ]; then printf 'U30_NETWORK_OK: unchanged\n';exit 0;fi
"$B/bin/mihomo" -t -d "$B/mihomo" -f "$D/candidate.yaml" > "$D/validation.log" 2>&1 || fail NETWORK_CANDIDATE_INVALID
ENDPOINT=$("$BB" awk '/^external-controller:/ {print $2;exit}' "$C")
case "$ENDPOINT" in 192.168.0.1:9090|192.168.0.1:19090|127.0.0.1:9090|127.0.0.1:19090) :;; *) fail CONTROLLER_ADDRESS_UNCONFIRMED;; esac
KEY=$("$BB" cat "$B/secret/admin.secret")
case "$KEY" in ''|*[!A-Za-z0-9._~@-]*) fail CONTROLLER_KEY_FORMAT;; esac
printf 'header = "Authorization: Bearer %s"\n' "$KEY" > "$D/auth";unset KEY
request(){
 method=$1;data=${2:-}
 if [ -n "$data" ]; then
 code=$("$CURL" --silent --show-error --noproxy '*' --max-time 15 --config "$D/auth" -H 'Content-Type: application/json' -X "$method" --data "$data" -o "$D/response" -w '%{http_code}' "http://$ENDPOINT/configs") || return 1
 else
 code=$("$CURL" --silent --show-error --noproxy '*' --max-time 15 --config "$D/auth" -X "$method" -o "$D/response" -w '%{http_code}' "http://$ENDPOINT/configs") || return 1
 fi
 [ "$code" = "${EXPECT:-204}" ]
}
EXPECT=200;request GET || fail CONTROLLER_READ_FAILED
MODE=$("$BB" grep -o '"mode":[[:space:]]*"[^"]*"' "$D/response" | "$BB" head -n1 | "$BB" cut -d '"' -f4)
case "$MODE" in rule|global|direct) :;; *) fail RUNTIME_MODE_UNCONFIRMED;; esac
EXPECT=204
CHANGED=0;COMMITTED=0;F=$B/mihomo/network-candidate-$$.yaml
cleanup(){
 rc=$?;trap - EXIT
 if [ "$rc" != 0 ] && [ "$CHANGED" = 1 ]; then
  "$BB" cp -p "$D/original.yaml" "$C"
  request PUT "{\"path\":\"$C\",\"force\":true}" >/dev/null 2>&1 || :
  request PATCH "{\"mode\":\"$MODE\"}" >/dev/null 2>&1 || :
 fi
 "$BB" rm -f "$F" "$D/auth" "$D/response"
 exit "$rc"
}
trap cleanup EXIT
"$BB" cp "$D/candidate.yaml" "$F";"$BB" chmod 600 "$F"
CHANGED=1
request PUT "{\"path\":\"$F\",\"force\":true}" || fail NETWORK_RELOAD_FAILED
request PATCH "{\"mode\":\"$MODE\"}" || fail MODE_RESTORE_FAILED
"$BB" cp "$D/candidate.yaml" "$C";"$BB" chmod 600 "$C"
request PUT "{\"path\":\"$C\",\"force\":true}" || fail NETWORK_PERSIST_RELOAD_FAILED
request PATCH "{\"mode\":\"$MODE\"}" || fail MODE_RESTORE_FAILED
COMMITTED=1
printf 'U30_NETWORK_OK: repaired\n'
printf 'Root-only backup: %s\n' "$D"
