#!/system/bin/sh
# Fixed device-local API operations; controller credentials never leave this process.
set -eu
umask 077
export LC_ALL=C
BASE=/data/adb/u30proxy
BB=/data/adb/magisk/busybox
CURL=/system/bin/curl
CTRL=http://192.168.0.1:9090
OP=${1:-status}
ARG=${2:-}
BODY=${3:-}
TMP=
cleanup() { [ -z "$TMP" ] || "$BB" rm -rf "$TMP"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
fail() { printf '%s\n' "$1"; exit "${2:-1}"; }
[ "$(id -u)" = 0 ] || fail root_required 77

if [ "$OP" = status ]; then
    if [ ! -x "$BASE/control.sh" ]; then
        printf 'deployment=missing\ncore=stopped\ntransparent=off\nautostart=no\nsubscription=none\ncontroller=not-ready\n'
        exit 0
    fi
    "$BASE/control.sh" status
    regional=present
    for region in hk jp tw us sg kr; do
        upper=$(printf '%s' "$region" | "$BB" tr 'a-z' 'A-Z')
        grep -Fq "RULE-SET,region-$region,REGION-$upper" "$BASE/mihomo/config.yaml" 2>/dev/null || regional=missing
        grep -Fq "name: REGION-$upper" "$BASE/mihomo/config.yaml" 2>/dev/null || regional=missing
        [ -s "$BASE/mihomo/rules/region-$region.yaml" ] && [ ! -L "$BASE/mihomo/rules/region-$region.yaml" ] || regional=missing
    done
    printf 'regional_rules=%s\n' "$regional"
    domestic=present
    for rule in geosite-private geoip-private geosite-cn geoip-cn; do
        grep -Fq "RULE-SET,$rule,DIRECT" "$BASE/mihomo/config.yaml" 2>/dev/null || domestic=missing
    done
    printf 'domestic_rules=%s\n' "$domestic"
    exit 0
fi

[ -x "$BB" ] && [ -x "$BASE/control.sh" ] || fail deployment_missing 78
case "$OP" in
    import_error)
        reason=$("$BB" cat "$BASE/run/subscription.last" 2>/dev/null || :)
        case "$reason" in download_http_403|download_http_401|download_failed|format_rejected|test_failed|api_failed|busy) printf '%s\n' "$reason";; *) printf 'unknown\n';; esac
        exit 0 ;;
    diagnostics)
        "$BASE/control.sh" status
        if ip -4 route get 223.5.5.5 >/dev/null 2>&1; then printf 'route=ready\n'; else printf 'route=missing\n'; fi
        if "$BB" timeout 6 "$BB" nslookup www.baidu.com >/dev/null 2>&1; then printf 'dns=ready\n'; else printf 'dns=failed\n'; fi
        direct=$("$CURL" --silent --noproxy '*' --connect-timeout 3 --max-time 6 --output /dev/null --write-out '%{http_code}' https://www.baidu.com 2>/dev/null || :)
        proxy=$("$CURL" --silent --noproxy '' --proxy http://127.0.0.1:7890 --connect-timeout 3 --max-time 6 --output /dev/null --write-out '%{http_code}' https://www.gstatic.com/generate_204 2>/dev/null || :)
        printf 'direct_http=%s\nproxy_http=%s\n' "$direct" "$proxy"
        exit 0 ;;
    enable)
        auto=0; [ ! -f "$BASE/run/autostart" ] || auto=1
        rc=0; "$BASE/control.sh" enable >/dev/null 2>&1 || rc=$?
        [ "$auto" = 1 ] || rm -f "$BASE/run/autostart"
        if [ "$rc" != 0 ]; then "$BASE/control.sh" disable >/dev/null 2>&1 || :; fail service_failed; fi
        printf 'done\n'; exit 0 ;;
    start|disable|restart|stop)
        "$BASE/control.sh" "$OP" >/dev/null 2>&1 || fail service_failed
        printf 'done\n'; exit 0 ;;
    management_start)
        rm -f "$BASE/run/enabled"
        "$BASE/control.sh" start >/dev/null 2>&1 || fail service_failed
        printf 'done\n'; exit 0 ;;
    refresh)
        "$BASE/update.sh" refresh >/dev/null 2>&1 || fail subscription_update_failed
        printf 'done\n'; exit 0 ;;
    autostart)
        test -x /data/adb/service.d/u30proxy.sh || fail startup_missing 78
        case "$ARG" in
            yes) "$BB" touch "$BASE/run/autostart" ;;
            no) "$BB" rm -f "$BASE/run/autostart" ;;
            *) fail invalid_argument 64 ;;
        esac
        printf 'done\n'; exit 0 ;;
    rollback_rules)
        R=$BASE/secret/standard-rules-latest
        [ -s "$R" ] && [ ! -L "$R" ] || fail rule_backup_missing 78
        P=$(cat "$R")
        case "$P" in "$BASE"/secret/standard-rules-*) ;; *) fail invalid_backup 78 ;; esac
        case "${P##*/}" in *[!A-Za-z0-9._-]*) fail invalid_backup 78 ;; esac
        [ ! -L "$P" ] && [ -f "$P/rollback.sh" ] && [ ! -L "$P/rollback.sh" ] || fail invalid_backup 78
        /system/bin/sh "$P/rollback.sh" >/dev/null 2>&1 || fail rule_restore_failed
        printf 'done\n'; exit 0 ;;
    import_ticket)
        [ -x "$BASE/admin/cgi-bin/platform-subscription.cgi" ] || fail channel_missing 78
        TROOT=$BASE/run/platform-import
        [ ! -L "$TROOT" ] || fail invalid_channel 78
        "$BB" mkdir -p "$TROOT"
        "$BB" chmod 700 "$TROOT"
        now=$("$BB" date +%s)
        for old in "$TROOT"/*; do
            [ -d "$old" ] && [ ! -L "$old" ] || continue
            old_name=${old##*/}
            case "$old_name" in ''|*[!0-9a-f]*) continue ;; esac
            [ "${#old_name}" = 64 ] || continue
            age=$("$BB" cat "$old/issued" 2>/dev/null || printf 0)
            case "$age" in ''|*[!0-9]*) continue ;; esac
            if [ -d "$old/used" ] && [ ! -f "$old/result" ] && [ "$age" -ge "$((now - 900))" ]; then
                continue
            fi
            [ "$age" -ge "$((now - 120))" ] || "$BB" rm -rf "$old"
        done
        ticket=$("$BB" od -An -N32 -tx1 /dev/urandom | "$BB" tr -d ' \n')
        case "$ticket" in ''|*[!0-9a-f]*) fail random_failed ;; esac
        [ "${#ticket}" = 64 ] || fail random_failed
        D=$TROOT/$ticket
        "$BB" mkdir "$D"
        "$BB" chmod 700 "$D"
        printf '%s\n' "$now" > "$D/issued"
        printf '{"ticket":"%s","expires":60}\n' "$ticket"
        exit 0 ;;
    import_poll|import_cancel)
        case "$ARG" in ''|*[!0-9a-f]*) fail invalid_argument 64 ;; esac
        [ "${#ARG}" = 64 ] || fail invalid_argument 64
        D=$BASE/run/platform-import/$ARG
        [ -d "$D" ] && [ ! -L "$D" ] || fail import_missing 78
        if [ "$OP" = import_cancel ]; then
            # A consumed ticket belongs to the background updater, not this UI.
            [ -d "$D/used" ] || "$BB" rm -rf "$D"
            printf 'done\n'; exit 0
        fi
        if [ -f "$D/result" ]; then
            rc=$("$BB" cat "$D/result")
            case "$rc" in ''|*[!0-9]*) fail invalid_result 78 ;; esac
            printf '__U30_IMPORT_RC__=%s\n' "$rc"
            "$BB" rm -rf "$D"
        else
            printf 'pending\n'
        fi
        exit 0 ;;
esac

case "$OP" in
    mode|proxies|providers|rules|connections|set_mode|select|delay|provider_delay|close_connection) ;;
    *) fail invalid_operation 64 ;;
esac
[ -x "$CURL" ] || fail curl_missing 78
[ -s "$BASE/secret/admin.secret" ] && [ ! -L "$BASE/secret/admin.secret" ] || fail key_missing 78
TMP=$("$BB" mktemp -d "$BASE/run/platform-api.XXXXXX") || fail temporary_storage_failed
"$BB" chmod 700 "$TMP"
key=$("$BB" cat "$BASE/secret/admin.secret")
case "$key" in ''|*[!A-Za-z0-9._~@-]*) fail key_invalid 78 ;; esac
[ "${#key}" -ge 16 ] && [ "${#key}" -le 256 ] || fail key_invalid 78
printf 'header = "Authorization: Bearer %s"\n' "$key" > "$TMP/curl.conf"
unset key
"$BB" chmod 600 "$TMP/curl.conf"
method=GET
path=
expect=200
case "$OP" in
    mode) path=/configs ;;
    proxies) path=/proxies ;;
    providers) path=/providers/proxies ;;
    rules) path=/rules ;;
    connections) path=/connections ;;
    set_mode)
        case "$ARG" in rule|global|direct) ;; *) fail invalid_mode 64 ;; esac
        method=PATCH; path=/configs; expect=204
        printf '{"mode":"%s"}' "$ARG" > "$TMP/body" ;;
    provider_delay)
        case "$ARG:$BODY" in *[!A-Za-z0-9._~%\!\(\)\*\'\-:]*) fail invalid_argument 64 ;; esac
        [ -n "$ARG" ] && [ -n "$BODY" ] && [ "${#ARG}" -le 2048 ] && [ "${#BODY}" -le 2048 ] || fail invalid_argument 64
        path=/providers/proxies/$ARG/$BODY/healthcheck?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204\&timeout=5000 ;;
    select|delay|close_connection)
        [ -n "$ARG" ] && [ "${#ARG}" -le 2048 ] || fail invalid_argument 64
        case "$ARG" in *[!A-Za-z0-9._~%\!\(\)\*\'\-]*) fail invalid_argument 64 ;; esac
        case "$OP" in
            select)
                [ -n "$BODY" ] && [ "${#BODY}" -le 4096 ] || fail invalid_argument 64
                method=PUT; path=/proxies/$ARG; expect=204
                printf '%s' "$BODY" > "$TMP/body" ;;
            delay) path=/proxies/$ARG/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204\&timeout=5000 ;;
            close_connection) method=DELETE; path=/connections/$ARG; expect=204 ;;
        esac ;;
esac
if [ -f "$TMP/body" ]; then
    code=$("$CURL" --silent --noproxy '*' --connect-timeout 3 --max-time 12 --max-filesize 4194304 \
        --config "$TMP/curl.conf" --header 'Content-Type: application/json' --request "$method" \
        --data-binary "@$TMP/body" --output "$TMP/response" --write-out '%{http_code}' "$CTRL$path" 2>/dev/null) || fail controller_offline 69
else
    code=$("$CURL" --silent --noproxy '*' --connect-timeout 3 --max-time 12 --max-filesize 4194304 \
        --config "$TMP/curl.conf" --request "$method" --output "$TMP/response" \
        --write-out '%{http_code}' "$CTRL$path" 2>/dev/null) || fail controller_offline 69
fi
[ "$code" = "$expect" ] || fail controller_request_failed 69
if [ "$OP" = mode ]; then
    mode=$("$BB" sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' "$TMP/response")
    case "$mode" in rule|global|direct) printf '{"mode":"%s"}\n' "$mode" ;; *) fail invalid_response 65 ;; esac
elif [ "$expect" = 204 ]; then
    printf '{"ok":true}\n'
else
    "$BB" cat "$TMP/response"
    printf '\n'
fi
