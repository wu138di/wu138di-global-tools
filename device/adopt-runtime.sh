#!/system/bin/sh
# Transactional public-script/tool migration. Never edits node YAML or secrets.
set -eu
umask 077
BASE=/data/adb/u30proxy
TOOLS=/data/adb/u30proxy-tools
SERVICE=/data/adb/service.d/u30proxy.sh
BB=$TOOLS/busybox
[ "$(id -u)" = 0 ] && [ -x "$BB" ] && [ -x "$TOOLS/http-tool" ] || exit 77
[ -d "$BASE" ] || { printf 'ADOPT_NOT_NEEDED\n';exit 0; }
[ ! -L "$BASE" ] && [ ! -L "$BASE/secret" ] && [ ! -L "$BASE/run" ] || exit 78
[ ! -f "$BASE/run/enabled" ] || { printf 'U30_PLUGIN_ERROR: STOP_PROXY_BEFORE_INSTALL\n';exit 1; }
B=$BASE/secret/engine-migration-$("$BB" date +%Y%m%dT%H%M%S)-$$
"$BB" mkdir "$B";"$BB" chmod 700 "$B"
FILES="control.sh update.sh admin/cgi-bin/manage.cgi admin/cgi-bin/platform-subscription.cgi"
for REL in $FILES;do
 F=$BASE/$REL
 [ -e "$F" ] || continue
 [ -f "$F" ] && [ ! -L "$F" ] || exit 78
 N=$(printf %s "$REL" | "$BB" tr / _)
 "$BB" cp -p "$F" "$B/$N.before"
 "$BB" sed \
  -e "s@/system/bin/curl@$TOOLS/http-tool@g" \
  -e "s@/data/data/com.minikano.f50_sms/files/curl@$TOOLS/http-tool@g" \
  -e "s@/data/user/0/com.minikano.f50_sms/files/curl@$TOOLS/http-tool@g" \
  -e "s@/data/adb/magisk/busybox@$TOOLS/busybox@g" \
  -e "s@/data/data/com.minikano.f50_sms/files/busybox@$TOOLS/busybox@g" \
  "$F" > "$B/$N.after"
 /system/bin/sh -n "$B/$N.after"
 printf '%s %s\n' "$N" "$F" >> "$B/files"
done
# The existing boot hook is left intact; it calls the same owned control script.
cat > "$B/rollback.sh" <<EOF
#!/system/bin/sh
set -eu
B=$B
BB=$BB
[ ! -L "\$B" ] && [ ! -f "$BASE/run/enabled" ] || exit 78
while read N F;do
 case "\$F" in "$BASE/control.sh"|"$BASE/update.sh"|"$BASE/admin/cgi-bin/manage.cgi"|"$BASE/admin/cgi-bin/platform-subscription.cgi") :;;*) exit 78;;esac
 [ ! -L "\$F" ] && [ -f "\$B/\$N.before" ] || exit 78
 "\$BB" cp "\$B/\$N.before" "\$F.restore";"\$BB" chmod 700 "\$F.restore";"\$BB" mv "\$F.restore" "\$F"
done < "\$B/files"
printf 'ENGINE_ADOPTION_ROLLED_BACK\\n'
EOF
"$BB" chmod 700 "$B/rollback.sh"
COMMIT=0
cleanup(){ R=$?;trap - EXIT HUP INT TERM;if [ "$COMMIT" != 1 ] && [ -s "$B/files" ];then /system/bin/sh "$B/rollback.sh" >/dev/null 2>&1 || :;fi;exit "$R"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
while read N F;do
 if "$BB" cmp -s "$B/$N.before" "$B/$N.after";then continue;fi
 "$BB" cp "$B/$N.after" "$F.new";"$BB" chmod 700 "$F.new";"$BB" mv "$F.new" "$F"
done < "$B/files"
COMMIT=1
printf 'ENGINE_ADOPTED\nrollback=%s/rollback.sh\n' "$B"
