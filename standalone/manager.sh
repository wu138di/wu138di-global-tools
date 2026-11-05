#!/system/bin/sh
set -eu
umask 077
H=/data/adb/wu-global
BB=$H/tools/busybox
PID=$H/state/manager.pid
[ "$(id -u)" = 0 ] || exit 77
[ -x "$BB" ] && [ ! -L "$H" ] && [ -f "$H/owned-marker" ] || exit 78
owned_pid() {
 [ -f "$PID" ] && [ ! -L "$PID" ] || return 1
 P=$(cat "$PID")
 case "$P" in ''|*[!0-9]*) return 1;; esac
 [ "$P" -gt 1 ] && kill -0 "$P" 2>/dev/null || return 1
 FIRST=$("$BB" tr '\000' '\n' < "/proc/$P/cmdline" | "$BB" head -n 1)
 [ "$FIRST" = "$H/global-manager" ]
}
case "${1:-status}" in
 status)
  if owned_pid; then printf 'manager=running\n'; else printf 'manager=stopped\n'; fi
  if [ -f /data/adb/service.d/wu-global-manager.sh ]; then printf 'manager_autostart=yes\n'; else printf 'manager_autostart=no\n'; fi
  ;;
 start)
  if owned_pid; then printf 'manager=running\n';exit 0;fi
  ss -lnt | "$BB" grep -E ':9088([[:space:]]|$)' >/dev/null && { printf 'MANAGER_PORT_OCCUPIED\n';exit 73; }
  [ -x "$H/global-manager" ] && [ ! -L "$H/global-manager" ] || exit 78
  "$BB" nohup "$H/global-manager" -home "$H" -listen 192.168.0.1:9088 > "$H/state/manager.log" 2>&1 </dev/null &
  NEW=$!
  printf '%s\n' "$NEW" > "$PID";chmod 600 "$PID"
  for N in 1 2 3 4 5 6 7 8 9 10; do
   owned_pid || { printf 'MANAGER_START_FAILED\n';exit 1; }
   if ss -lnt | "$BB" grep -E '192\.168\.0\.1:9088([[:space:]]|$)' >/dev/null; then printf 'manager=running\nurl=https://192.168.0.1:9088\n';exit 0;fi
   "$BB" sleep 1
  done
  printf 'MANAGER_LISTENER_UNCONFIRMED\n';exit 1
  ;;
 stop)
  if owned_pid; then kill "$P";for N in 1 2 3 4 5 6; do kill -0 "$P" 2>/dev/null || break;"$BB" sleep 1;done;kill -0 "$P" 2>/dev/null && { printf 'MANAGER_STOP_UNCONFIRMED\n';exit 1; };fi
  rm -f "$PID";printf 'manager=stopped\n'
  ;;
 boot-on)
  [ -d /data/adb/service.d ] && [ ! -L /data/adb/service.d ] || exit 78
  F=/data/adb/service.d/wu-global-manager.sh
  [ ! -L "$F" ] || exit 78
  if [ -e "$F" ]; then "$BB" grep -F '# wu-global-manager-owned-v1' "$F" >/dev/null || exit 78;fi
  cat > "$F.new" <<'BOOT'
#!/system/bin/sh
# wu-global-manager-owned-v1
while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 3; done
/system/bin/sh /data/adb/wu-global/manager.sh start >/dev/null 2>&1
BOOT
  chmod 700 "$F.new";mv "$F.new" "$F";printf 'manager_autostart=yes\n'
  ;;
 boot-off)
  F=/data/adb/service.d/wu-global-manager.sh
  [ ! -L "$F" ] || exit 78
  if [ -e "$F" ]; then "$BB" grep -F '# wu-global-manager-owned-v1' "$F" >/dev/null || exit 78;rm -f "$F";fi
  printf 'manager_autostart=no\n'
  ;;
 *) exit 64;;
esac
