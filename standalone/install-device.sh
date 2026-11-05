#!/system/bin/sh
# Installs only the independent manager. No proxy, routing or DNS changes.
set -eu
umask 077
S=${1:-}
H=/data/adb/wu-global
case "$S" in /data/local/tmp/wu-global-transfer-*) ;; *) exit 64;; esac
case "${S##*/}" in *[!A-Za-z0-9_-]*) exit 64;; esac
[ "$(id -u)" = 0 ] || { printf 'ROOT_REQUIRED\n';exit 77; }
[ "$(getprop ro.product.cpu.abi)" = arm64-v8a ] || exit 78
[ ! -L "$S" ] && [ -f "$S/global-manager-arm64" ] && [ ! -L "$S/global-manager-arm64" ] || exit 78
[ ! -L /data/adb ] && [ ! -L "$H" ] || exit 78
cd "$S"
sha256sum -c DEVICE-SHA256SUMS.txt >/dev/null || { printf 'PACKAGE_HASH_MISMATCH\n';exit 65; }
/system/bin/sh "$S/root-env.sh" prepare
case "$(getprop ro.product.model)" in
 MU5358|U30*|*U30*Pro*) VARIANT=u30;;
 F50) [ "$(getprop ro.product.device)" = MU300 ] && [ "$(getprop ro.build.display.id)" = F50SPV1.0.0B08 ] || exit 78;VARIANT=f50;;
 *) printf 'DEVICE_NOT_VALIDATED\n';exit 78;;
esac
STAMP=$(date +%Y%m%dT%H%M%S)-$$
B=/data/adb/wu-global-backup-$STAMP
[ ! -e "$B" ] && [ ! -L "$B" ] || exit 78
mkdir "$B";chmod 700 "$B"
HAD=0;WAS_RUNNING=0
if [ -e "$H" ]; then
 [ -d "$H" ] && [ -f "$H/owned-marker" ] && [ ! -L "$H/owned-marker" ] || exit 78
 [ "$(cat "$H/owned-marker")" = wu-global-standalone-v1 ] || exit 78
 HAD=1
 /system/bin/sh "$H/manager.sh" status | grep -Fx 'manager=running' >/dev/null && WAS_RUNNING=1 || :
 /system/bin/sh "$H/manager.sh" stop
 cp -Rp "$H" "$B/previous"
else
 mkdir "$H";chmod 700 "$H"
 printf 'wu-global-standalone-v1\n' > "$H/owned-marker"
fi
cat > "$B/rollback.sh" <<EOF
#!/system/bin/sh
set -eu
H=/data/adb/wu-global
B=$B
[ "\$(id -u)" = 0 ] && [ ! -L "\$H" ] && [ ! -L "\$B" ] || exit 78
[ -f "\$H/owned-marker" ] && [ "\$(cat "\$H/owned-marker")" = wu-global-standalone-v1 ] || exit 78
if [ -x "\$H/manager.sh" ] && [ -x "\$H/tools/busybox" ]; then /system/bin/sh "\$H/manager.sh" stop;elif [ -e "\$H/state/manager.pid" ]; then exit 78;fi
[ ! -e "\$B/retired" ] && [ ! -L "\$B/retired" ] || exit 78
mv "\$H" "\$B/retired"
if [ "$HAD" = 1 ]; then cp -Rp "\$B/previous" "\$H";if [ "$WAS_RUNNING" = 1 ]; then /system/bin/sh "\$H/manager.sh" start;fi;fi
printf 'ROLLBACK_OK_PROXY_FILES_UNCHANGED\\n'
EOF
chmod 700 "$B/rollback.sh"
COMMITTED=0
cleanup(){ R=$?;trap - EXIT HUP INT TERM;if [ "$COMMITTED" != 1 ]; then /system/bin/sh "$B/rollback.sh" >/dev/null 2>&1 || :;fi;exit "$R"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
cp "$S/global-manager-arm64" "$H/global-manager.new";chmod 700 "$H/global-manager.new";mv "$H/global-manager.new" "$H/global-manager"
cp "$S/manager.sh" "$H/manager.sh";chmod 700 "$H/manager.sh"
"$H/global-manager" -prepare -home "$H" -variant "$VARIANT"
T=/data/adb/u30proxy-tools
[ ! -L "$T" ] || exit 78
mkdir -p "$T";chmod 700 "$T"
if [ ! -e "$T/busybox" ]; then cp "$H/tools/busybox" "$T/busybox";chmod 700 "$T/busybox";fi
[ ! -L "$T/busybox" ] && [ -x "$T/busybox" ] && "$T/busybox" true || exit 78
# Self-built HTTP helper: no system curl or companion app is needed.
[ -x "$H/tools/http-tool" ] && [ ! -L "$T/http-tool" ] || exit 78
NEW_HASH=$(sha256sum "$H/tools/http-tool");NEW_HASH=${NEW_HASH%% *}
if [ -e "$T/http-tool" ];then
 [ -f "$T/.http-tool.sha256" ] && [ ! -L "$T/.http-tool.sha256" ] || exit 78
 OLD_HASH=$(sha256sum "$T/http-tool");OLD_HASH=${OLD_HASH%% *}
 [ "$OLD_HASH" = "$(cat "$T/.http-tool.sha256")" ] || exit 78
fi
cp "$H/tools/http-tool" "$T/http-tool.new";chmod 700 "$T/http-tool.new";mv "$T/http-tool.new" "$T/http-tool"
printf '%s\n' "$NEW_HASH" > "$T/.http-tool.sha256";chmod 600 "$T/.http-tool.sha256"
"$T/http-tool" --version >/dev/null || exit 69
# Do not touch the pre-existing proxy files or either service.d hook.
printf '%s\n' "$B/rollback.sh" > "$H/state/rollback-path"
"$H/tools/busybox" sha256sum "$H/global-manager" "$H/manager.sh" > "$B/installed.sha256"
/system/bin/sh "$H/manager.sh" start
COMMITTED=1
printf 'STANDALONE_INSTALL_OK\nvariant=%s\nproxy_state=unchanged\nmanager_autostart=unchanged\nrollback=%s/rollback.sh\n' "$VARIANT" "$B"
