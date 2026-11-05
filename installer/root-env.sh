#!/system/bin/sh
# Root readiness and owned service-directory provisioning; no partition writes.
set -eu
umask 077
[ "$(id -u)" = 0 ] || { printf 'ROOT_REQUIRED\n';exit 77; }
for D in /data/adb /data/adb/service.d; do [ ! -L "$D" ] || exit 78;done
FRAMEWORK=unknown
if command -v magisk >/dev/null 2>&1 && magisk -V >/dev/null 2>&1;then FRAMEWORK=magisk
elif [ -d /data/adb/ksu ];then FRAMEWORK=kernelsu
elif [ -d /data/adb/ap ];then FRAMEWORK=apatch
fi
if [ ! -d /data/adb/service.d ];then
 [ "$FRAMEWORK" != unknown ] || { printf 'BOOT_MANAGER_UNCONFIRMED\n';exit 78; }
 if [ "${1:-check}" = prepare ];then mkdir /data/adb/service.d;chmod 700 /data/adb/service.d
 else printf 'service_directory=missing\n';exit 78;fi
fi
printf 'root=ready\nframework=%s\nservice_directory=ready\n' "$FRAMEWORK"
