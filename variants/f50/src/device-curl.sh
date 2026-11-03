CURL=
for candidate in /system/bin/curl /data/data/com.minikano.f50_sms/files/curl /data/user/0/com.minikano.f50_sms/files/curl; do
    if [ -x "$candidate" ]; then CURL=$candidate; break; fi
done
if [ -z "$CURL" ]; then printf '%s\n' 'UFI_COMPAT_ERROR: CURL_REQUIRED; network unchanged' >&2; exit 69; fi
