# Resolve only known root/UFI locations; never download or install root tools.
BB=
for candidate in /data/adb/magisk/busybox /data/adb/u30proxy-tools/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/data/com.minikano.f50_sms/files/busybox /data/user/0/com.minikano.f50_sms/files/busybox; do
    if [ -x "$candidate" ] && "$candidate" true 2>/dev/null; then
        BB=$candidate
        break
    fi
done
if [ -z "$BB" ]; then
    printf '%s\n' 'UFI_COMPAT_ERROR: BUSYBOX_REQUIRED; no supported BusyBox found; network unchanged' >&2
    exit 69
fi
