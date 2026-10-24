#!/system/bin/sh
# Single-use import channel on the existing admin HTTP server. No new listener.
set -u
umask 077
export LC_ALL=C
BASE=/data/adb/u30proxy
BB=/data/adb/magisk/busybox
D=
CONSUMED=0

reply() {
    printf 'Status: %s\r\nContent-Type: application/json; charset=utf-8\r\n' "$1"
    printf 'Cache-Control: no-store\r\nPragma: no-cache\r\nX-Content-Type-Options: nosniff\r\n'
    printf 'Referrer-Policy: no-referrer\r\nVary: Origin\r\n'
    printf 'Access-Control-Allow-Origin: http://192.168.0.1:2333\r\n'
    printf 'Access-Control-Allow-Methods: POST, OPTIONS\r\n'
    printf 'Access-Control-Allow-Headers: authorization, content-type\r\n'
    printf 'Access-Control-Max-Age: 60\r\n\r\n%s\n' "$2"
    exit 0
}
cleanup() {
    if [ "$CONSUMED" = 1 ] && [ -n "$D" ]; then
        "$BB" rm -f "$D/url" "$D/mode" "$D/runner.sh"
        [ -f "$D/result" ] || printf '1\n' > "$D/result"
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
case "${REMOTE_ADDR:-}" in 192.168.0.*) ;; *) reply '403 Forbidden' '{"ok":false,"error":"lan_only"}' ;; esac
[ "${HTTP_HOST:-}" = 192.168.0.1:9091 ] || reply '403 Forbidden' '{"ok":false,"error":"invalid_host"}'
[ "${HTTP_ORIGIN:-}" = http://192.168.0.1:2333 ] || reply '403 Forbidden' '{"ok":false,"error":"invalid_origin"}'
if [ "${REQUEST_METHOD:-}" = OPTIONS ]; then
    [ "${HTTP_ACCESS_CONTROL_REQUEST_METHOD:-}" = POST ] || reply '405 Method Not Allowed' '{"ok":false}'
    reply '204 No Content' ''
fi
[ "${REQUEST_METHOD:-}" = POST ] || reply '405 Method Not Allowed' '{"ok":false,"error":"method_not_allowed"}'
case "${CONTENT_TYPE:-}" in text/plain|text/plain\;*) ;; *) reply '415 Unsupported Media Type' '{"ok":false,"error":"plain_text_required"}' ;; esac
case "${QUERY_STRING:-}" in ''|mode=subscription) IMPORT_MODE=set; LIMIT=8192;; mode=yaml) IMPORT_MODE=yaml; LIMIT=1048576;; *) reply '400 Bad Request' '{"ok":false}' ;; esac
length=${CONTENT_LENGTH:-0}
case "$length" in ''|*[!0-9]*) reply '411 Length Required' '{"ok":false,"error":"length_required"}' ;; esac
[ "${#length}" -le 7 ] || reply '413 Content Too Large' '{"ok":false,"error":"body_too_large"}'
length=$(printf '%s' "$length" | "$BB" sed 's/^0*//')
[ -n "$length" ] && [ "$length" -ge 1 ] && [ "$length" -le "$LIMIT" ] || reply '413 Content Too Large' '{"ok":false,"error":"body_too_large"}'
case "${HTTP_AUTHORIZATION:-}" in 'Bearer '*) ticket=${HTTP_AUTHORIZATION#Bearer } ;; *) reply '401 Unauthorized' '{"ok":false,"error":"ticket_required"}' ;; esac
case "$ticket" in ''|*[!0-9a-f]*) reply '401 Unauthorized' '{"ok":false,"error":"ticket_invalid"}' ;; esac
[ "${#ticket}" = 64 ] || reply '401 Unauthorized' '{"ok":false,"error":"ticket_invalid"}'
D=$BASE/run/platform-import/$ticket
[ -d "$D" ] && [ ! -L "$D" ] && [ -f "$D/issued" ] && [ ! -L "$D/issued" ] || reply '401 Unauthorized' '{"ok":false,"error":"ticket_invalid"}'
[ ! -d "$D/used" ] || reply '409 Conflict' '{"ok":false,"error":"ticket_used"}'
issued=$("$BB" cat "$D/issued")
now=$("$BB" date +%s)
case "$issued" in ''|*[!0-9]*) reply '401 Unauthorized' '{"ok":false,"error":"ticket_invalid"}' ;; esac
[ "$issued" -le "$now" ] && [ "$issued" -ge "$((now - 60))" ] || { "$BB" rm -rf "$D"; reply '401 Unauthorized' '{"ok":false,"error":"ticket_expired"}'; }
"$BB" mkdir "$D/used" 2>/dev/null || reply '409 Conflict' '{"ok":false,"error":"ticket_used"}'
CONSUMED=1
unset ticket HTTP_AUTHORIZATION
"$BB" head -c "$length" > "$D/url" || reply '400 Bad Request' '{"ok":false,"error":"invalid_body"}'
"$BB" chmod 600 "$D/url"
actual=$("$BB" wc -c < "$D/url")
[ "$actual" -eq "$length" ] || reply '400 Bad Request' '{"ok":false,"error":"incomplete_body"}'
printf '%s\n' "$IMPORT_MODE" > "$D/mode"
# The existing transactional updater revalidates HTTPS, length, TLS and YAML.
cat > "$D/runner.sh" <<'U30_SUB_RUNNER'
#!/system/bin/sh
set -u
umask 077
D=${0%/*}
BB=/data/adb/magisk/busybox
cleanup() { "$BB" rm -f "$D/url" "$D/mode" "$D/runner.sh"; }
trap cleanup EXIT
trap 'printf "1\n" > "$D/result"; exit 1' HUP INT TERM
MODE=$("$BB" cat "$D/mode")
case "$MODE" in set|yaml) ;; *) exit 64 ;; esac
/data/adb/u30proxy/update.sh "$MODE" < "$D/url" >/dev/null 2>&1
rc=$?
"$BB" rm -f "$D/url"
printf '%s\n' "$rc" > "$D/result.tmp"
"$BB" mv "$D/result.tmp" "$D/result"
exit "$rc"
U30_SUB_RUNNER
"$BB" chmod 700 "$D/runner.sh"
/system/bin/sh -n "$D/runner.sh" || reply '500 Internal Server Error' '{"ok":false,"error":"runner_invalid"}'
"$BB" nohup /system/bin/sh "$D/runner.sh" >/dev/null 2>&1 </dev/null &
CONSUMED=0
reply '202 Accepted' '{"ok":true,"result":"started"}'
