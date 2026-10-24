#!/system/bin/sh
# U30 Pro / MU5358 public install-or-start action for UFI-TOOLS.
# Existing complete installs are preserved. No private node, URL token or key is embedded.
set -eu
umask 077
export LC_ALL=C
BASE=/data/adb/u30proxy
BB=/data/adb/magisk/busybox
CURL=/system/bin/curl
CORE_SHA=bb9afbd48717f92d59e07da35fb694b83d40d6edb63eb9033c2ee4174137d195
S=
FRESH=0
PROBE_OWNED=0
PLUGIN_LOCK=/data/adb/u30proxy-plugin-install.lock
PLUGIN_LOCK_HELD=0
fail() { printf 'U30_PLUGIN_ERROR: %s\n' "$1" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail ROOT_REQUIRED
[ -x "$BB" ] && [ -x "$CURL" ] || fail MAGISK_BUSYBOX_AND_SYSTEM_CURL_REQUIRED
cleanup() {
    rc=$?
    if [ "$PROBE_OWNED" = 1 ]; then probe_cleanup; fi
    if [ "$rc" -ne 0 ] && [ "$FRESH" = 1 ] && [ -f "$BASE/control.sh" ]; then
        /system/bin/sh "$BASE/control.sh" rollback >/dev/null 2>&1 || :
        printf 'Fresh install stopped; files preserved for inspection: %s\n' "$BASE" >&2
    fi
    if [ -n "$S" ] && [ -n "${BACKUP:-}" ] && [ -d "$BACKUP" ]; then
        for diagnostic in "$S"/*.log; do
            [ -f "$diagnostic" ] && "$BB" cp "$diagnostic" "$BACKUP/" || :
        done
    fi
    if [ -n "$S" ]; then
        case "$S" in /data/adb/u30proxy-plugin-stage-*) "$BB" rm -rf "$S";; esac
    fi
    if [ "$PLUGIN_LOCK_HELD" = 1 ] && [ -f "$PLUGIN_LOCK/pid" ] && [ "$("$BB" cat "$PLUGIN_LOCK/pid")" = "$$" ]; then
        "$BB" rm -f "$PLUGIN_LOCK/pid"
        "$BB" rmdir "$PLUGIN_LOCK" || :
    fi
    trap - EXIT HUP INT TERM
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
"$BB" mkdir "$PLUGIN_LOCK" 2>/dev/null || fail ANOTHER_INSTALL_ACTION_OR_STALE_LOCK
"$BB" chmod 700 "$PLUGIN_LOCK"
printf '%s\n' "$$" > "$PLUGIN_LOCK/pid"
PLUGIN_LOCK_HELD=1
hash_ok() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$("$BB" sha256sum "$1" | "$BB" cut -d ' ' -f 1)" = "$2" ]; }
secret_ok() {
    [ -s "$BASE/secret/admin.secret" ] && [ ! -L "$BASE/secret/admin.secret" ] || return 1
    key=$("$BB" cat "$BASE/secret/admin.secret")
    case "$key" in ''|*[!A-Za-z0-9._~@-]*) key=; return 1;; esac
    [ "${#key}" -ge 16 ] && [ "${#key}" -le 256 ] || { key=; return 1; }
    key=
}
[ "$(getprop ro.product.cpu.abi)" = arm64-v8a ] || fail ARM64_ANDROID_REQUIRED
case "$(getprop ro.product.model)" in MU5358|U30*|*U30*Pro*) :;; *) fail SUPPORTED_U30_MODEL_REQUIRED;; esac
[ -d /sys/class/net/br0 ] && [ -d /sys/class/net/sipa_eth0 ] || fail U30_LAN_WAN_INTERFACES_REQUIRED
ip -4 -o addr show dev br0 | "$BB" grep -E 'inet 192\.168\.0\.1/24([[:space:]]|$)' >/dev/null || fail LAN_192_168_0_1_24_REQUIRED
for tool in ip iptables ip6tables ss getprop sha256sum; do command -v "$tool" >/dev/null 2>&1 || fail SYSTEM_NETWORK_TOOLS_REQUIRED; done
[ -d /data/adb/service.d ] && [ ! -L /data/adb/service.d ] || fail MAGISK_SERVICE_DIRECTORY_REQUIRED
if [ -e "$BASE" ] || [ -L "$BASE" ]; then
    [ -d "$BASE" ] && [ ! -L "$BASE" ] || fail EXISTING_BASE_PRESERVED_NOT_A_DIRECTORY
    for d in bin mihomo mihomo/providers mihomo/rules mihomo/ui admin admin/cgi-bin secret run; do
        [ -d "$BASE/$d" ] && [ ! -L "$BASE/$d" ] || fail EXISTING_PARTIAL_BASE_PRESERVED
    done
    for f in control.sh update.sh admin/index.html admin/cgi-bin/manage.cgi mihomo/config.yaml mihomo/providers/subscription.yaml mihomo/ui/index.html mihomo/ui/u30-subscription.js; do
        [ -s "$BASE/$f" ] && [ ! -L "$BASE/$f" ] || fail EXISTING_PARTIAL_BASE_PRESERVED
    done
    for f in geoip-cn.mrs geoip-private.mrs geosite-cn.mrs geosite-private.mrs custom-direct.yaml custom-proxy.yaml region-jp.yaml region-hk.yaml region-tw.yaml region-us.yaml region-sg.yaml region-kr.yaml; do
        [ -s "$BASE/mihomo/rules/$f" ] && [ ! -L "$BASE/mihomo/rules/$f" ] || fail EXISTING_PARTIAL_RULES_PRESERVED
    done
    [ -x "$BASE/control.sh" ] && [ -x "$BASE/update.sh" ] && [ -x "$BASE/bin/mihomo" ] || fail EXISTING_PARTIAL_EXECUTABLES_PRESERVED
    [ -s /data/adb/service.d/u30proxy.sh ] && [ ! -L /data/adb/service.d/u30proxy.sh ] || fail EXISTING_STARTUP_MISSING_PRESERVED
    "$BB" grep -F '/data/adb/u30proxy' /data/adb/service.d/u30proxy.sh >/dev/null || fail EXISTING_STARTUP_DIFFERENT_PRESERVED
    secret_ok || fail EXISTING_PRIVATE_KEY_INVALID_PRESERVED
    "$BASE/bin/mihomo" -v >/dev/null 2>&1 || fail EXISTING_CORE_INVALID_PRESERVED
    for f in "$BASE/control.sh" "$BASE/update.sh" "$BASE/admin/cgi-bin/manage.cgi" /data/adb/service.d/u30proxy.sh; do
        /system/bin/sh -n "$f" || fail EXISTING_SCRIPT_SYNTAX_PRESERVED
    done
    S=/data/adb/u30proxy-plugin-stage-$("$BB" date +%Y%m%dT%H%M%S)-$$
    "$BB" mkdir "$S" || fail PRIVATE_CHECK_DIRECTORY_FAILED
    "$BB" chmod 700 "$S"
    for f in mihomo/config.yaml mihomo/providers/subscription.yaml secret/admin.secret; do
        "$BB" sha256sum "$BASE/$f" >> "$S/private.before.sha256"
    done
    "$BASE/bin/mihomo" -t -d "$BASE/mihomo" > "$S/config-check.log" 2>&1 || fail EXISTING_CONFIG_INVALID_PRESERVED
    /system/bin/sh "$BASE/control.sh" start > "$S/start.log" 2>&1 || fail EXISTING_START_FAILED_WITH_FILES_PRESERVED
    /system/bin/sh "$BASE/control.sh" status > "$S/status.txt"
    for state in core=running controller=authenticated-ready admin=running watchdog=running; do
        "$BB" grep -F -x "$state" "$S/status.txt" >/dev/null || fail EXISTING_SERVICE_NOT_READY
    done
    "$BB" sha256sum -c "$S/private.before.sha256" >/dev/null || fail EXISTING_PRIVATE_FILES_CHANGED
    "$BB" cat "$S/status.txt"
    printf '%s\n' 'U30_PLUGIN_OK: existing configuration, subscription, secret and selection cache preserved; no downloads or source reset.'
    exit 0
fi
[ ! -e /data/adb/service.d/u30proxy.sh ] && [ ! -L /data/adb/service.d/u30proxy.sh ] || fail STARTUP_EXISTS_WITHOUT_BASE_PRESERVED
for family in iptables ip6tables; do
    "$family" -t mangle -S | "$BB" grep -E '(^-N U30P_|^-A .* U30P_)' >/dev/null && fail OWNED_CHAIN_CONFLICT_PRESERVED || :
done
ip -4 rule show | "$BB" grep -E '(^9000:|lookup 20230)' >/dev/null && fail ROUTING_TUPLE_CONFLICT_PRESERVED || :
ip -6 rule show | "$BB" grep -E '(^9000:|lookup 20230)' >/dev/null && fail ROUTING_TUPLE_CONFLICT_PRESERVED || :
ss -lntu | "$BB" grep -E ':(7890|7893|1053|9090|9091)([[:space:]]|$)' >/dev/null && fail SERVICE_PORT_CONFLICT_PRESERVED || :
free_kb=$("$BB" df -Pk /data | "$BB" awk 'NR==2 {print $4}')
case "$free_kb" in ''|*[!0-9]*) fail DISK_CHECK_FAILED;; esac
[ "$free_kb" -ge 180000 ] || fail AT_LEAST_180_MB_DATA_SPACE_REQUIRED
S=/data/adb/u30proxy-plugin-stage-$("$BB" date +%Y%m%dT%H%M%S)-$$
"$BB" mkdir "$S" || fail PRIVATE_STAGE_DIRECTORY_FAILED
"$BB" chmod 700 "$S"
export U30_STAGE="$S"
BACKUP=/data/adb/u30proxy-plugin-backup-$("$BB" date +%Y%m%dT%H%M%S)-$$
"$BB" mkdir "$BACKUP"
"$BB" chmod 700 "$BACKUP"
{
    id; getprop ro.product.model; getprop ro.product.cpu.abi; getprop ro.build.display.id
    getprop ro.boot.slot_suffix; getprop sys.boot_completed; getenforce
    ip -o addr show br0; ip -4 rule show; ip -6 rule show
    ip -4 route show table all; ip -6 route show table all; ss -lntu
} > "$BACKUP/preflight.log" 2>&1
iptables-save > "$BACKUP/iptables.before"
ip6tables-save > "$BACKUP/ip6tables.before"
ip -4 rule show > "$BACKUP/ip4-rule.before"
ip -6 rule show > "$BACKUP/ip6-rule.before"
ip -4 route show table all > "$BACKUP/ip4-route.before"
ip -6 route show table all > "$BACKUP/ip6-route.before"
"$BB" sha256sum /data/adb/service.d/* > "$BACKUP/startup.before.sha256" 2>/dev/null || :
"$BB" chmod 600 "$BACKUP"/*
cat > "$S/control.sh" <<'U30_PUBLIC_CONTROL_SH_EOF'
#!/system/bin/sh
# U30 proxy lifecycle. Only U30P_* chains and the dedicated routing tuple are owned.
set -eu
umask 077

BASE=/data/adb/u30proxy
SELF=$BASE/control.sh
BB=/data/adb/magisk/busybox
CORE=$BASE/bin/mihomo
CONF_DIR=$BASE/mihomo
CONF=$CONF_DIR/config.yaml
RUN=$BASE/run
SECRET_FILE=$BASE/secret/admin.secret
LAN=br0
LAN_IP=192.168.0.1
MARK=0x40000000/0x40000000
TABLE=20230
PREF=9000
LOCK=$RUN/control.lock
LOCK_HELD=0
TRANSACTION=0
NEW_CORE=0
NEW_ADMIN=0
NEW_WORKER=0
ACTION=${1:-status}
IPT=$(command -v iptables)
IP6T=$(command -v ip6tables)
IP=$(command -v ip)
CURL=/system/bin/curl

[ "$(id -u)" = 0 ] || { printf '%s\n' 'root required'; exit 1; }
[ -x "$BB" ] || { printf '%s\n' 'BusyBox missing'; exit 1; }
mkdir -p "$RUN"
chmod 700 "$RUN"

log() {
    printf '%s %s\n' "$("$BB" date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$RUN/control.log"
}

rotate_logs() {
    for rl_file in "$RUN/control.log" "$RUN/core.log" "$RUN/admin.log" "$RUN/worker.log" "$RUN/update.log"; do
        [ -f "$rl_file" ] || continue
        rl_size=$("$BB" stat -c %s "$rl_file" 2>/dev/null || printf 0)
        case "$rl_size" in ''|*[!0-9]*) rl_size=0;; esac
        if [ "$rl_size" -gt 524288 ]; then
            "$BB" tail -c 131072 "$rl_file" > "$rl_file.1" || :
            : > "$rl_file"
        fi
    done
}

ipt() { "$IPT" -w 5 "$@"; }
ip6t() { "$IP6T" -w 5 "$@"; }

pid_number() {
    case "$1" in ''|*[!0-9]*|0|1) return 1;; esac
    [ -r "/proc/$1/cmdline" ] && kill -0 "$1" 2>/dev/null
}

proc_arg() {
    "$BB" tr '\000' '\n' < "/proc/$1/cmdline" 2>/dev/null | "$BB" grep -F -x -- "$2" >/dev/null 2>&1
}

pid_matches() {
    pm_role=$1
    pm_pid=$2
    pid_number "$pm_pid" || return 1
    case "$pm_role" in
        core)
            pm_first=$("$BB" tr '\000' '\n' < "/proc/$pm_pid/cmdline" | "$BB" head -n 1)
            [ "$pm_first" = "$CORE" ] && proc_arg "$pm_pid" "$CONF"
            ;;
        admin)
            proc_arg "$pm_pid" "$BB" && proc_arg "$pm_pid" httpd && proc_arg "$pm_pid" "$BASE/admin" && proc_arg "$pm_pid" "$LAN_IP:9091"
            ;;
        worker)
            proc_arg "$pm_pid" "$SELF" && proc_arg "$pm_pid" watchdog
            ;;
        updater)
            proc_arg "$pm_pid" "$BASE/update.sh"
            ;;
        *) return 1;;
    esac
}

role_alive() {
    ra_role=$1
    if [ -s "$RUN/$ra_role.pid" ]; then
        ra_pid=$(cat "$RUN/$ra_role.pid" 2>/dev/null || :)
        if pid_matches "$ra_role" "$ra_pid"; then return 0; fi
    fi
    # pgrep supplies only broad candidates; exact argv remains the ownership gate.
    case "$ra_role" in
        core) ra_pattern=$CORE;;
        admin) ra_pattern=$BASE/admin;;
        worker) ra_pattern=$SELF;;
        updater) ra_pattern=$BASE/update.sh;;
        *) return 1;;
    esac
    ra_candidates=$("$BB" pgrep -f "$ra_pattern" 2>/dev/null || :)
    for ra_pid in $ra_candidates; do
        [ "$ra_pid" != "$$" ] || continue
        if pid_matches "$ra_role" "$ra_pid"; then
            save_pid "$ra_role" "$ra_pid"
            return 0
        fi
    done
    return 1
} 2>/dev/null

save_pid() {
    printf '%s\n' "$2" > "$RUN/$1.pid.tmp"
    mv -f "$RUN/$1.pid.tmp" "$RUN/$1.pid"
}

lock_owner_alive() {
    pid_number "$1" && { proc_arg "$1" "$SELF" || proc_arg "$1" "$BASE/update.sh"; }
}

kill_role() {
    kr_role=$1
    # pgrep is candidate discovery only: every signal still requires exact argv.
    case "$kr_role" in
        core) kr_pattern=$CORE;;
        admin) kr_pattern=$BASE/admin;;
        worker) kr_pattern=$SELF;;
        updater) kr_pattern=$BASE/update.sh;;
        *) return 1;;
    esac
    kr_candidates=$("$BB" pgrep -f "$kr_pattern" 2>/dev/null || :)
    for kr_pid in $kr_candidates; do
        if [ "$kr_pid" != "$$" ] && pid_matches "$kr_role" "$kr_pid"; then
            kill -TERM "$kr_pid" 2>/dev/null || :
            kr_wait=0
            while pid_matches "$kr_role" "$kr_pid" && [ "$kr_wait" -lt 5 ]; do
                sleep 1
                kr_wait=$((kr_wait + 1))
            done
            if pid_matches "$kr_role" "$kr_pid"; then
                kill -KILL "$kr_pid" 2>/dev/null || :
            fi
        fi
    done
    rm -f "$RUN/$kr_role.pid" "$RUN/$kr_role.pid.tmp"
} 2>/dev/null

take_lock() {
    tl_count=0
    while ! mkdir "$LOCK" 2>/dev/null; do
        tl_count=$((tl_count + 1))
        [ "$tl_count" -lt 180 ] || { log 'control lock timed out'; return 1; }
        tl_pid=$(cat "$LOCK/pid" 2>/dev/null || :)
        if ! lock_owner_alive "$tl_pid"; then
            # Give the mkdir winner time to publish its owner before stale recovery.
            sleep 5
            tl_pid=$(cat "$LOCK/pid" 2>/dev/null || :)
        fi
        if ! lock_owner_alive "$tl_pid"; then
            if [ -d "$LOCK/recover" ]; then
                tl_recover_pid=$(cat "$LOCK/recover/pid" 2>/dev/null || :)
                if ! lock_owner_alive "$tl_recover_pid"; then
                    # The update script publishes a recovery owner in this directory.
                    # Kill-9 recovery is allowed only after both owners remain dead.
                    sleep 5
                    tl_recover_pid=$(cat "$LOCK/recover/pid" 2>/dev/null || :)
                    tl_pid=$(cat "$LOCK/pid" 2>/dev/null || :)
                    if ! lock_owner_alive "$tl_pid" && ! lock_owner_alive "$tl_recover_pid"; then
                        rm -f "$LOCK/recover/pid"
                        rmdir "$LOCK/recover" 2>/dev/null || :
                    fi
                fi
            fi
            tl_pid=$(cat "$LOCK/pid" 2>/dev/null || :)
            if ! lock_owner_alive "$tl_pid" && [ ! -d "$LOCK/recover" ]; then
                rm -f "$LOCK/pid"
                rmdir "$LOCK" 2>/dev/null || :
            else
                sleep 1
            fi
        else
            sleep 1
        fi
    done
    printf '%s\n' "$$" > "$LOCK/pid"
    LOCK_HELD=1
}

drop_lock() {
    if [ "$LOCK_HELD" = 1 ]; then
        rm -f "$LOCK/pid"
        rmdir "$LOCK" 2>/dev/null || :
        LOCK_HELD=0
    fi
}

remove_transparent() {
    while ipt -t mangle -D PREROUTING -i "$LAN" -j U30P_M4 >/dev/null 2>&1; do :; done
    while ipt -t nat -D PREROUTING -i "$LAN" -j U30P_D4 >/dev/null 2>&1; do :; done
    while ip6t -t mangle -D PREROUTING -i "$LAN" -j U30P_M6 >/dev/null 2>&1; do :; done
    while ip6t -t filter -D FORWARD -j U30P_F6 >/dev/null 2>&1; do :; done
    while ip6t -t filter -D U30P_I6 -i "$LAN" -p udp --dport 53 -j REJECT --reject-with icmp6-port-unreachable >/dev/null 2>&1; do :; done
    while ip6t -t filter -D U30P_I6 -i "$LAN" -p tcp --dport 53 -j REJECT --reject-with tcp-reset >/dev/null 2>&1; do :; done
    ipt -t mangle -F U30P_M4 >/dev/null 2>&1 || :
    ipt -t mangle -X U30P_M4 >/dev/null 2>&1 || :
    ipt -t nat -F U30P_D4 >/dev/null 2>&1 || :
    ipt -t nat -X U30P_D4 >/dev/null 2>&1 || :
    ip6t -t mangle -F U30P_M6 >/dev/null 2>&1 || :
    ip6t -t mangle -X U30P_M6 >/dev/null 2>&1 || :
    ip6t -t filter -F U30P_F6 >/dev/null 2>&1 || :
    ip6t -t filter -X U30P_F6 >/dev/null 2>&1 || :
    while "$IP" rule del pref "$PREF" fwmark "$MARK" table "$TABLE" >/dev/null 2>&1; do :; done
    while "$IP" -6 rule del pref "$PREF" fwmark "$MARK" table "$TABLE" >/dev/null 2>&1; do :; done
    "$IP" route del local 0.0.0.0/0 dev lo table "$TABLE" >/dev/null 2>&1 || :
    "$IP" -6 route del local ::/0 dev lo table "$TABLE" >/dev/null 2>&1 || :
    rm -f "$RUN/transparent" "$RUN/lan6-prefixes"
}

remove_protection() {
    while ipt -t filter -D INPUT -j U30P_I4 >/dev/null 2>&1; do :; done
    while ip6t -t filter -D INPUT -j U30P_I6 >/dev/null 2>&1; do :; done
    ipt -t filter -F U30P_I4 >/dev/null 2>&1 || :
    ipt -t filter -X U30P_I4 >/dev/null 2>&1 || :
    ip6t -t filter -F U30P_I6 >/dev/null 2>&1 || :
    ip6t -t filter -X U30P_I6 >/dev/null 2>&1 || :
}

cleanup_rules() {
    remove_transparent
    remove_protection
}

on_exit() {
    oe_rc=$?
    trap - EXIT HUP INT TERM
    set +e
    if [ "$TRANSACTION" = 1 ]; then
        remove_transparent
        [ "$NEW_WORKER" = 0 ] || kill_role worker
        kill_role admin
        kill_role core
        remove_protection
        log "transaction rolled back (exit=$oe_rc)"
    fi
    drop_lock
    exit "$oe_rc"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

api_ready() {
    role_alive core || return 1
    [ -s "$SECRET_FILE" ] || return 1
    ar_secret=$(cat "$SECRET_FILE") || return 1
    "$CURL" --noproxy '*' -fsS --connect-timeout 2 --max-time 4 -H "Authorization: Bearer $ar_secret" "http://$LAN_IP:9090/version" >/dev/null 2>&1
}

wait_lan() {
    wl_n=0
    while [ "$wl_n" -lt 120 ]; do
        if [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ] && "$IP" -4 addr show dev "$LAN" 2>/dev/null | "$BB" grep -F "inet $LAN_IP/" >/dev/null; then
            return 0
        fi
        wl_n=$((wl_n + 1))
        sleep 1
    done
    log 'boot or LAN readiness timed out'
    return 1
}

install_protection() {
    ipt -t filter -N U30P_I4
    ip6t -t filter -N U30P_I6
    for pr_proto in tcp udp; do
        # OEM mangle INPUT changes nfmark after routing. Match the transparent
        # socket itself as well, including the core's wildcard listening socket.
        ipt -t filter -A U30P_I4 -i "$LAN" -p "$pr_proto" -m socket --transparent --nowildcard -j ACCEPT
        ip6t -t filter -A U30P_I6 -i "$LAN" -p "$pr_proto" -m socket --transparent --nowildcard -j ACCEPT
        ipt -t filter -A U30P_I4 -i "$LAN" -p "$pr_proto" -m mark --mark "$MARK" -j ACCEPT
        ip6t -t filter -A U30P_I6 -i "$LAN" -p "$pr_proto" -m mark --mark "$MARK" -j ACCEPT
        for pr_if in lo "$LAN"; do
            ipt -t filter -A U30P_I4 -i "$pr_if" -p "$pr_proto" -m multiport --dports 7890,7893,1053,9090,9091 -j ACCEPT
            ip6t -t filter -A U30P_I6 -i "$pr_if" -p "$pr_proto" -m multiport --dports 7890,7893,1053,9090,9091 -j ACCEPT
        done
        ipt -t filter -A U30P_I4 -p "$pr_proto" -m multiport --dports 7890,7893,1053,9090,9091 -j DROP
        ip6t -t filter -A U30P_I6 -p "$pr_proto" -m multiport --dports 7890,7893,1053,9090,9091 -j DROP
    done
    ipt -t filter -A U30P_I4 -j RETURN
    ip6t -t filter -A U30P_I6 -j RETURN
    ipt -t filter -I INPUT 1 -j U30P_I4
    ip6t -t filter -I INPUT 1 -j U30P_I6
}

connected_lan6() {
    "$IP" -6 route show dev "$LAN" | "$BB" awk '
        /proto kernel/ && index($1, ":") && $1 != "::/0" {
            p = tolower($1)
            if (p !~ /^fe80/ && p !~ /^ff/) print $1
        }
    ' | "$BB" sort -u
}

install_transparent() {
    "$IP" route add local 0.0.0.0/0 dev lo table "$TABLE"
    "$IP" rule add pref "$PREF" fwmark "$MARK" table "$TABLE"
    "$IP" -6 route add local ::/0 dev lo table "$TABLE"
    "$IP" -6 rule add pref "$PREF" fwmark "$MARK" table "$TABLE"
    ipt -t mangle -N U30P_M4
    ipt -t nat -N U30P_D4
    ip6t -t mangle -N U30P_M6
    ip6t -t filter -N U30P_F6
    # This firmware has no xt_addrtype. Enumerate exact current local addresses.
    for tp_local4 in $("$IP" -o -4 addr show | "$BB" awk '{sub(/\/.*/, "", $4); print $4}'); do
        ipt -t mangle -A U30P_M4 -d "$tp_local4/32" -j RETURN
    done
    for tp_local6 in $("$IP" -o -6 addr show | "$BB" awk '{sub(/\/.*/, "", $4); print $4}'); do
        ip6t -t mangle -A U30P_M6 -d "$tp_local6/128" -j RETURN
    done
    for tp_net in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
        ipt -t mangle -A U30P_M4 -d "$tp_net" -j RETURN
    done
    for tp_net6 in ::/128 ::1/128 ::ffff:0:0/96 fc00::/7 fe80::/10 ff00::/8; do
        ip6t -t mangle -A U30P_M6 -d "$tp_net6" -j RETURN
    done
    # Preserve on-link global IPv6 LAN traffic without hard-coding a delegated prefix.
    connected_lan6 > "$RUN/lan6-prefixes"
    while IFS= read -r tp_lan6; do
        [ -n "$tp_lan6" ] || continue
        ip6t -t mangle -A U30P_M6 -d "$tp_lan6" -j RETURN
    done < "$RUN/lan6-prefixes"
    for tp_proto in tcp udp; do
        ipt -t mangle -A U30P_M4 -p "$tp_proto" --dport 53 -j RETURN
        ip6t -t mangle -A U30P_M6 -p "$tp_proto" --dport 53 -j RETURN
        ipt -t mangle -A U30P_M4 -p "$tp_proto" -j TPROXY --on-ip 0.0.0.0 --on-port 7893 --tproxy-mark "$MARK"
        ip6t -t mangle -A U30P_M6 -p "$tp_proto" -j TPROXY --on-ip :: --on-port 7893 --tproxy-mark "$MARK"
        ipt -t nat -A U30P_D4 -p "$tp_proto" --dport 53 -j REDIRECT --to-ports 1053
    done
    ip6t -t filter -I U30P_I6 1 -i "$LAN" -p udp --dport 53 -j REJECT --reject-with icmp6-port-unreachable
    ip6t -t filter -I U30P_I6 1 -i "$LAN" -p tcp --dport 53 -j REJECT --reject-with tcp-reset
    ip6t -t filter -A U30P_F6 -i "$LAN" -p udp --dport 53 -j REJECT --reject-with icmp6-port-unreachable
    ip6t -t filter -A U30P_F6 -i "$LAN" -p tcp --dport 53 -j REJECT --reject-with tcp-reset
    ip6t -t filter -A U30P_F6 -j RETURN
    ip6t -t filter -I FORWARD 1 -j U30P_F6
    ipt -t nat -I PREROUTING 1 -i "$LAN" -j U30P_D4
    ipt -t mangle -I PREROUTING 1 -i "$LAN" -j U30P_M4
    ip6t -t mangle -I PREROUTING 1 -i "$LAN" -j U30P_M6
    : > "$RUN/transparent"
}

protection_ready() {
    ipt -t filter -C INPUT -j U30P_I4 >/dev/null 2>&1 && ip6t -t filter -C INPUT -j U30P_I6 >/dev/null 2>&1
}

transparent_ready() {
    [ -f "$RUN/transparent" ] &&
    [ -f "$RUN/lan6-prefixes" ] &&
    [ "$(connected_lan6)" = "$(cat "$RUN/lan6-prefixes")" ] &&
    ipt -t mangle -C PREROUTING -i "$LAN" -j U30P_M4 >/dev/null 2>&1 &&
    ipt -t nat -C PREROUTING -i "$LAN" -j U30P_D4 >/dev/null 2>&1 &&
    ip6t -t mangle -C PREROUTING -i "$LAN" -j U30P_M6 >/dev/null 2>&1 &&
    ip6t -t filter -C FORWARD -j U30P_F6 >/dev/null 2>&1 &&
    "$IP" rule show | "$BB" grep -E "^$PREF:.*fwmark 0x40000000/0x40000000.*lookup $TABLE" >/dev/null &&
    "$IP" -6 rule show | "$BB" grep -E "^$PREF:.*fwmark 0x40000000/0x40000000.*lookup $TABLE" >/dev/null &&
    "$IP" route show table "$TABLE" | "$BB" grep -E '^local default dev lo' >/dev/null &&
    "$IP" -6 route show table "$TABLE" | "$BB" grep -E '^local (default|::/0) dev lo' >/dev/null
}

start_admin() {
    role_alive admin && return 0
    [ -d "$BASE/admin" ] || { log 'admin document root missing'; return 1; }
    if [ -f "$BASE/admin/httpd.conf" ]; then
        "$BB" nohup "$BB" httpd -f -p "$LAN_IP:9091" -h "$BASE/admin" -c "$BASE/admin/httpd.conf" >> "$RUN/admin.log" 2>&1 < /dev/null &
    else
        "$BB" nohup "$BB" httpd -f -p "$LAN_IP:9091" -h "$BASE/admin" >> "$RUN/admin.log" 2>&1 < /dev/null &
    fi
    save_pid admin "$!"
    NEW_ADMIN=1
    sleep 1
    role_alive admin || { log 'admin process startup failed'; return 1; }
}

start_worker() {
    role_alive worker && return 0
    "$BB" nohup /system/bin/sh "$SELF" watchdog >> "$RUN/worker.log" 2>&1 < /dev/null &
    save_pid worker "$!"
    NEW_WORKER=1
    sleep 1
    role_alive worker || { log 'watchdog process startup failed'; return 1; }
}

start_locked() {
    TRANSACTION=1
    wait_lan
    [ -x "$CORE" ] && [ -s "$CONF" ] && [ -s "$SECRET_FILE" ] || { log 'core, configuration, or admin secret missing'; exit 1; }
    if ! "$CORE" -t -d "$CONF_DIR" -f "$CONF" > /dev/null 2>&1; then
        log 'configuration validation failed; transparent routing cleared'
        exit 1
    fi
    # Protection is needed even for the authenticated readiness request: OEM INPUT
    # drops TCP 9090. Transparency is installed only after readiness succeeds.
    cleanup_rules
    install_protection
    if ! api_ready; then
        remove_transparent
        kill_role core
        "$BB" nohup "$CORE" -d "$CONF_DIR" -f "$CONF" >> "$RUN/core.log" 2>&1 < /dev/null &
        save_pid core "$!"
        NEW_CORE=1
        sleep 1
        sl_n=0
        while ! api_ready; do
            sl_n=$((sl_n + 1))
            [ "$sl_n" -lt 20 ] || { log 'core authenticated API readiness failed'; exit 1; }
            role_alive core || { log 'core process exited during startup'; exit 1; }
            sleep 1
        done
    fi
    if [ -f "$RUN/enabled" ] && [ -f "$RUN/subscription.valid" ]; then
        install_transparent
        transparent_ready || { log 'transparent routing verification failed'; exit 1; }
    else
        log 'transparency disabled or no validated subscription; direct core only'
    fi
    protection_ready || { log 'INPUT protection verification failed'; exit 1; }
    start_admin
    : > "$RUN/active"
    if [ "${1:-worker}" != no-worker ]; then start_worker; fi
    TRANSACTION=0
    NEW_CORE=0
    NEW_ADMIN=0
    NEW_WORKER=0
    log 'service ready; authenticated API verified'
    rotate_logs
}

stop_locked() {
    remove_transparent
    rm -f "$RUN/active"
    kill_role worker
    kill_role updater
    kill_role admin
    kill_role core
    remove_protection
    log 'service stopped; owned transparent routes removed'
}

tick_locked() {
    [ -f "$RUN/active" ] || return 0
    tk_healthy=1
    api_ready || tk_healthy=0
    protection_ready || tk_healthy=0
    role_alive admin || tk_healthy=0
    if [ -f "$RUN/enabled" ] && [ -f "$RUN/subscription.valid" ]; then
        transparent_ready || tk_healthy=0
    elif [ -f "$RUN/transparent" ] || ipt -t mangle -C PREROUTING -i "$LAN" -j U30P_M4 >/dev/null 2>&1; then
        tk_healthy=0
    fi
    if [ "$tk_healthy" = 0 ]; then
        log 'watchdog detected unhealthy service; removing transparent routing before recovery'
        cleanup_rules
        kill_role core
        start_locked no-worker
    fi
    rotate_logs
}

watchdog_loop() {
    wd_last=$("$BB" date +%s)
    while [ -f "$RUN/active" ]; do
        sleep 10
        [ -f "$RUN/active" ] || break
        /system/bin/sh "$SELF" __tick >/dev/null 2>&1 || :
        wd_now=$("$BB" date +%s)
        if [ "$((wd_now - wd_last))" -ge 3600 ]; then
            wd_last=$wd_now
            if [ -f "$RUN/active" ] && [ -f "$BASE/update.sh" ] && ! role_alive updater; then
                "$BB" timeout -s TERM 180 /system/bin/sh "$BASE/update.sh" >> "$RUN/update.log" 2>&1 < /dev/null &
                save_pid updater "$!"
            fi
        fi
    done
}

show_status() {
    if role_alive core; then printf 'core=running\n'; else printf 'core=stopped\n'; fi
    if [ -f "$RUN/enabled" ]; then printf 'enabled=yes\n'; else printf 'enabled=no\n'; fi
    if [ -f "$RUN/autostart" ]; then printf 'autostart=yes\n'; else printf 'autostart=no\n'; fi
    if [ -f "$RUN/subscription.valid" ]; then printf 'subscription=validated\n'; else printf 'subscription=none\n'; fi
    if transparent_ready; then printf 'transparent=on\n'; else printf 'transparent=off\n'; fi
    if protection_ready; then printf 'input_protection=on\n'; else printf 'input_protection=off\n'; fi
    if api_ready; then printf 'controller=authenticated-ready\n'; else printf 'controller=not-ready\n'; fi
    if role_alive admin; then printf 'admin=running\n'; else printf 'admin=stopped\n'; fi
    if role_alive worker; then printf 'watchdog=running\n'; else printf 'watchdog=stopped\n'; fi
}

case "$ACTION" in
    status) show_status;;
    watchdog) watchdog_loop;;
    start) take_lock; start_locked;;
    stop) take_lock; stop_locked;;
    enable) take_lock; : > "$RUN/autostart"; : > "$RUN/enabled"; start_locked;;
    disable)
        take_lock
        rm -f "$RUN/enabled"
        remove_transparent
        log 'transparent proxy disabled; core, admin, and INPUT protection retained'
        ;;
    restart) take_lock; stop_locked; start_locked;;
    boot)
        [ -f "$RUN/autostart" ] || exit 0
        take_lock
        [ -f "$RUN/autostart" ] || exit 0
        start_locked
        ;;
    __tick) take_lock; tick_locked;;
    rollback)
        take_lock
        rm -f "$RUN/enabled" "$RUN/autostart"
        stop_locked
        if [ -f /data/adb/service.d/u30proxy.sh ]; then
            if "$BB" grep -F "$BASE" /data/adb/service.d/u30proxy.sh >/dev/null 2>&1; then
                rm -f /data/adb/service.d/u30proxy.sh
                log 'project boot entry removed; deployment and backups retained'
            else
                log 'unrelated boot entry preserved'
            fi
        fi
        ;;
    *) printf '%s\n' 'usage: control.sh status|start|stop|enable|disable|restart|watchdog|boot|rollback'; exit 2;;
esac
U30_PUBLIC_CONTROL_SH_EOF
cat > "$S/update.sh" <<'U30_PUBLIC_UPDATE_SH_EOF'
#!/system/bin/sh
# Private, transactional Mihomo file-provider updater. No URL or node log output.
set -u
umask 077
export LC_ALL=C
BASE=/data/adb/u30proxy
BB=/data/adb/magisk/busybox
CURL=/system/bin/curl
BIN=$BASE/bin/mihomo
HOME_DIR=$BASE/mihomo
PROVIDER=$HOME_DIR/providers/subscription.yaml
URLFILE=$BASE/secret/subscription.url
KEYFILE=$BASE/secret/admin.secret
VALID=$BASE/run/subscription.valid
LOCK=$BASE/run/subscription.lock
CONTROL_LOCK=$BASE/run/control.lock
CTRL=http://192.168.0.1:9090
MODE=${1:-refresh}
TMP=
COMMITTED=0
SWAPPED=0
RECOVER_API=0
CONTROL_HELD=0
PAUSE_TRANSPARENT=0
RESULT=

owner_live() {
    owner_pid=$("$BB" cat "$1/pid" 2>/dev/null || :)
    case "$owner_pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$owner_pid" 2>/dev/null || return 1
    owner_cmd=$("$BB" tr '\000' ' ' < "/proc/$owner_pid/cmdline" 2>/dev/null || :)
    case "$owner_cmd" in *"$BASE/update.sh"*|*"$BASE/control.sh"*) return 0 ;; *) return 1 ;; esac
}

release_control() {
    if [ "$CONTROL_HELD" = 1 ] && [ "$("$BB" cat "$CONTROL_LOCK/pid" 2>/dev/null)" = "$$" ]; then
        "$BB" rm -rf "$CONTROL_LOCK"
    fi
    CONTROL_HELD=0
}

take_control() {
    control_wait=0
    while ! "$BB" mkdir "$CONTROL_LOCK" 2>/dev/null; do
        if owner_live "$CONTROL_LOCK"; then
            control_wait=$((control_wait + 1))
            [ "$control_wait" -le 30 ] || return 1
            "$BB" sleep 1
            continue
        fi
        # A just-created lock may not have its PID yet; give it a grace period.
        control_wait=$((control_wait + 1))
        [ "$control_wait" -gt 5 ] || { "$BB" sleep 1; continue; }
        if ! "$BB" mkdir "$CONTROL_LOCK/recover" 2>/dev/null; then
            owner_live "$CONTROL_LOCK/recover" && return 1
            [ "$control_wait" -gt 10 ] || { "$BB" sleep 1; continue; }
            "$BB" rm -f "$CONTROL_LOCK/recover/pid"
            "$BB" rmdir "$CONTROL_LOCK/recover" 2>/dev/null || return 1
            continue
        fi
        printf '%s\n' "$$" > "$CONTROL_LOCK/recover/pid"
        if owner_live "$CONTROL_LOCK"; then
            "$BB" rm -f "$CONTROL_LOCK/recover/pid"
            "$BB" rmdir "$CONTROL_LOCK/recover"
            return 1
        fi
        printf '%s\n' "$$" > "$CONTROL_LOCK/pid"
        "$BB" rm -f "$CONTROL_LOCK/recover/pid"
        "$BB" rmdir "$CONTROL_LOCK/recover"
        CONTROL_HELD=1
        return 0
    done
    printf '%s\n' "$$" > "$CONTROL_LOCK/pid"
    CONTROL_HELD=1
    return 0
}

note() {
    # Only fixed result identifiers are passed to this function.
    printf '%s\n' "$1" > "$BASE/run/subscription.last"
    printf '%s subscription %s\n' "$("$BB" date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$BASE/run/control.log"
}

api_refresh() {
    code=$("$CURL" --silent --show-error --noproxy '*' --connect-timeout 3 --max-time 20 \
        --config "$TMP/api.conf" --request PUT --output "$TMP/api.body" \
        --write-out '%{http_code}' "$CTRL/providers/proxies/subscription" 2>/dev/null) || return 1
    [ "$code" = 204 ]
}

api_has_proxy_nodes() {
    code=$("$CURL" --silent --show-error --noproxy '*' --connect-timeout 3 --max-time 20 \
        --config "$TMP/api.conf" --output "$TMP/provider.api.json" \
        --write-out '%{http_code}' "$CTRL/providers/proxies/subscription" 2>/dev/null) || return 1
    [ "$code" = 200 ] || return 1
    # These values are generated by Mihomo's parsed adapters, not supplied YAML
    # labels. Exclude Direct/Reject/DNS/Pass and all non-node provider types.
    "$BB" grep -Eq '"type"[[:space:]]*:[[:space:]]*"(Shadowsocks|ShadowsocksR|Snell|Socks5|Http|Vmess|Vless|Trojan|Hysteria|Hysteria2|WireGuard|Tuic|Ssh|Mieru|AnyTLS|Sudoku|Masque|TrustTunnel|ShadowQuic|OpenVPN|Tailscale|ZeroTier|EasyTier|GostRelay)"' "$TMP/provider.api.json"
}

restore_files() {
    old=$1
    [ -e "$old/changed" ] || return 0
    [ -e "$old/committed" ] && return 0
    [ -s "$old/provider.old" ] || return 1
    "$BB" cp "$old/provider.old" "$PROVIDER.recover.$$" || return 1
    "$BB" chmod 600 "$PROVIDER.recover.$$"
    "$BB" mv -f "$PROVIDER.recover.$$" "$PROVIDER" || return 1
    if [ -e "$old/had_url" ]; then
        "$BB" cp "$old/url.old" "$URLFILE.recover.$$" || return 1
        "$BB" chmod 600 "$URLFILE.recover.$$"
        "$BB" mv -f "$URLFILE.recover.$$" "$URLFILE" || return 1
    else
        "$BB" rm -f "$URLFILE"
    fi
    if [ -e "$old/had_valid" ]; then
        "$BB" touch "$VALID"
    else
        "$BB" rm -f "$VALID"
    fi
    return 0
}

cleanup() {
    rc=$?
    trap - EXIT HUP INT TERM
    if [ "$COMMITTED" != 1 ] && [ "$SWAPPED" = 1 ]; then
        if restore_files "$TMP"; then
            if ! api_refresh >/dev/null 2>&1; then
                RESULT=recovery_api_failed
                note recovery_api_failed
                PAUSE_TRANSPARENT=1
            fi
        else
            note recovery_failed
            release_control
            printf 'recovery_failed\n'
            # Keep the transaction for the next invocation to recover.
            exit 74
        fi
    fi
    release_control
    if [ "$PAUSE_TRANSPARENT" = 1 ]; then
        "$BASE/control.sh" disable >/dev/null 2>&1 || :
    fi
    [ -n "$TMP" ] && "$BB" rm -rf "$TMP"
    if [ -f "$LOCK/pid" ] && [ "$("$BB" cat "$LOCK/pid" 2>/dev/null)" = "$$" ]; then
        "$BB" rm -rf "$LOCK"
    fi
    [ -z "$RESULT" ] || printf '%s\n' "$RESULT"
    exit "$rc"
}

fail() {
    note "$1"
    RESULT=$1
    exit "${2:-1}"
}

case "$MODE" in set|refresh) ;; *) printf 'invalid_mode\n'; exit 64 ;; esac
[ -x "$BB" ] && [ -x "$CURL" ] && [ -x "$BIN" ] || { printf 'missing_runtime\n'; exit 69; }
"$BB" mkdir -p "$BASE/run" "$BASE/secret" "$HOME_DIR/providers" || exit 73
"$BB" chmod 700 "$BASE/secret"

# mkdir is the shared manual/automatic lock. PID ownership is also checked
# against /proc command lines, so a reboot's unrelated reused PID is not a lock.
tries=0
acquired=0
while ! "$BB" mkdir "$LOCK" 2>/dev/null; do
    owner_live "$LOCK" && { printf 'busy\n'; exit 75; }
    tries=$((tries + 1))
    [ "$tries" -gt 5 ] || { "$BB" sleep 1; continue; }
    # Claim recovery inside the existing directory, preserving exclusion while
    # recovering its transaction instead of racing rm/mkdir against another job.
    if ! "$BB" mkdir "$LOCK/recover" 2>/dev/null; then
        claim_pid=$("$BB" cat "$LOCK/recover/pid" 2>/dev/null || :)
        case "$claim_pid" in
            ''|*[!0-9]*)
                [ "$tries" -gt 10 ] || { "$BB" sleep 1; continue; }
                ;;
            *) owner_live "$LOCK/recover" && { printf 'busy\n'; exit 75; } ;;
        esac
        "$BB" rm -f "$LOCK/recover/pid"
        "$BB" rmdir "$LOCK/recover" 2>/dev/null || { printf 'busy\n'; exit 75; }
        continue
    fi
    printf '%s\n' "$$" > "$LOCK/recover/pid"
    if owner_live "$LOCK"; then
        "$BB" rm -rf "$LOCK/recover"
        printf 'busy\n'; exit 75
    fi
    printf '%s\n' "$$" > "$LOCK/pid"
    if [ -e "$LOCK/work/changed" ] && [ ! -e "$LOCK/work/committed" ]; then
        take_control || { printf 'busy\n'; exit 75; }
        if ! restore_files "$LOCK/work"; then
            release_control
            printf 'recovery_failed\n'; exit 74
        fi
        RECOVER_API=1
    fi
    "$BB" rm -rf "$LOCK/work" "$LOCK/recover"
    acquired=1
    break
done
[ "$acquired" = 1 ] || printf '%s\n' "$$" > "$LOCK/pid"
TMP=$LOCK/work
"$BB" mkdir -p "$TMP" || exit 73
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

key=$("$BB" cat "$KEYFILE" 2>/dev/null || :)
case "$key" in ''|*[!A-Za-z0-9._~@-]*) fail invalid_key 78 ;; esac
[ "${#key}" -ge 16 ] && [ "${#key}" -le 256 ] || fail invalid_key 78
printf 'header = "Authorization: Bearer %s"\n' "$key" > "$TMP/api.conf"
unset key
if [ "$RECOVER_API" = 1 ]; then
    api_refresh >/dev/null 2>&1 || { PAUSE_TRANSPARENT=1; note recovery_api_failed; }
    release_control
fi

if [ "$MODE" = set ]; then
    "$BB" dd bs=1 count=8193 of="$TMP/url.input" 2>/dev/null || fail input_failed 65
else
    [ -s "$URLFILE" ] || fail not_configured 78
    "$BB" cp "$URLFILE" "$TMP/url.input" || fail input_failed 65
fi
size=$("$BB" wc -c < "$TMP/url.input")
[ "$size" -gt 0 ] && [ "$size" -le 8192 ] || fail invalid_url 65
without_nul=$("$BB" tr -d '\000' < "$TMP/url.input" | "$BB" wc -c)
[ "$without_nul" -eq "$size" ] || fail invalid_url 65
url=$("$BB" sed 's/\r$//' "$TMP/url.input")
case "$url" in
    https://?*) ;;
    *) fail invalid_url 65 ;;
esac
case "$url" in *'
'*) fail invalid_url 65 ;; esac
printf '%s' "$url" | "$BB" grep -q '[^!-~]' && fail invalid_url 65
# Reject a missing authority or embedded credentials. Query tokens remain private.
authority=${url#https://}
authority=${authority%%/*}
authority=${authority%%\?*}
authority=${authority%%\#*}
case "$authority" in ''|*@*) fail invalid_url 65 ;; esac
printf '%s\n' "$url" > "$TMP/url.valid"
# Escape only for curl's data configuration; never evaluate user input.
printf '%s' "$url" | "$BB" sed 's/\\/\\\\/g;s/"/\\"/g' > "$TMP/url.escaped"
{ printf 'url = "'; "$BB" cat "$TMP/url.escaped"; printf '"\n'; } > "$TMP/download.conf"
unset url authority

# Use the system CA trust. TLS errors retain the old URL/provider, never -k.
( ulimit -f 16384 2>/dev/null || :
  "$CURL" --fail --silent --show-error --noproxy '*' \
    --user-agent 'clash.meta' \
    --proto '=https' --proto-redir '=https' --location --max-redirs 4 \
    --connect-timeout 15 --max-time 90 --max-filesize 8388608 \
    --config "$TMP/download.conf" --output "$TMP/download.yaml" 2>/dev/null
) || fail download_failed 69
size=$("$BB" wc -c < "$TMP/download.yaml")
[ "$size" -gt 0 ] && [ "$size" -le 8388608 ] || fail download_failed 69

# Extract the standard top-level YAML proxies section. Full Clash configurations
# are accepted, but unrelated rules/controllers/URLs never replace root config.
# Nonstandard base64 subscriptions and external YAML aliases are deliberately
# rejected instead of contacting any conversion service.
"$BB" awk '
    BEGIN { active=0; seen=0; nodes=0 }
    { sub(/\r$/, "") }
    NR==1 { sub(/^\357\273\277/, "") }
    /^(proxies|"proxies"|\047proxies\047)[[:space:]]*:/ {
        if (seen++) exit 2
        active=1
        line=$0
        sub(/^[^:]*:/, "", line)
        if (line ~ /^[[:space:]]*\[[[:space:]]*[^][[:space:]#]/) nodes=1
        print
        next
    }
    active {
        if ($0 !~ /^[[:space:]]/ && $0 !~ /^-/ && $0 !~ /^#/ && $0 !~ /^$/) { active=0; next }
        if ($0 ~ /^[[:space:]]*-[[:space:]]*[^#[:space:]]/) nodes=1
        print
    }
    END { if (seen != 1 || nodes != 1) exit 3 }
' "$TMP/download.yaml" > "$TMP/provider.yaml" || fail format_rejected 65

"$BB" mkdir "$TMP/node-test" || fail test_failed 73
{
    printf 'mixed-port: 0\nallow-lan: false\nmode: rule\nlog-level: error\nipv6: false\ndns:\n  enable: false\n'
    "$BB" cat "$TMP/provider.yaml"
    printf '\nrules:\n  - MATCH,DIRECT\n'
} > "$TMP/node-test/config.yaml"
# Validator output may contain node details, so discard it instead of logging.
"$BB" timeout 45 "$BIN" -t -d "$TMP/node-test" -f "$TMP/node-test/config.yaml" >/dev/null 2>&1 \
    || fail test_failed 65

# Copy the actual home, including local rules/custom YAML, into a private test
# directory. Relative provider/rule paths therefore refer only to test copies.
"$BB" mkdir "$TMP/home-test" || fail test_failed 73
"$BB" cp -R "$HOME_DIR/." "$TMP/home-test/" >/dev/null 2>&1 || fail test_failed 73
"$BB" cp "$TMP/provider.yaml" "$TMP/home-test/providers/subscription.yaml" || fail test_failed 73
"$BB" timeout 60 "$BIN" -t -d "$TMP/home-test" -f "$TMP/home-test/config.yaml" >/dev/null 2>&1 \
    || fail test_failed 65

# A validated candidate is still not committed until the live provider API loads
# it successfully. Never restart/kill the functioning core or management httpd.
take_control || fail busy 75
[ -s "$PROVIDER" ] || fail baseline_missing 78
"$BB" cp "$PROVIDER" "$TMP/provider.old" || fail backup_failed 73
if [ -e "$URLFILE" ]; then
    "$BB" cp "$URLFILE" "$TMP/url.old" || fail backup_failed 73
    "$BB" touch "$TMP/had_url"
fi
[ -e "$VALID" ] && "$BB" touch "$TMP/had_valid"
"$BB" cp "$TMP/provider.yaml" "$PROVIDER.new.$$" || fail install_failed 73
"$BB" chmod 600 "$PROVIDER.new.$$"
"$BB" touch "$TMP/changed" || fail install_failed 73
SWAPPED=1
"$BB" mv -f "$PROVIDER.new.$$" "$PROVIDER" || fail install_failed 73
api_refresh || fail api_failed 69
api_has_proxy_nodes || fail format_rejected 65
"$BB" mv -f "$TMP/url.valid" "$URLFILE" || fail install_failed 73
"$BB" chmod 600 "$URLFILE"
"$BB" touch "$VALID" || fail install_failed 73
"$BB" touch "$TMP/committed" || fail install_failed 73
COMMITTED=1
PAUSE_TRANSPARENT=0
release_control
"$BB" date -u +%Y-%m-%dT%H:%M:%SZ > "$BASE/run/subscription.updated"
note committed
printf 'committed\n'
exit 0
U30_PUBLIC_UPDATE_SH_EOF
cat > "$S/admin.html" <<'U30_PUBLIC_ADMIN_HTML_EOF'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'">
  <title>U30 Pro · 订阅管理</title>
  <style>
    :root{color-scheme:light dark;--bg:#f5f5f7;--card:#fff;--fg:#1d1d1f;--muted:#707078;--line:#e3e3e8;--blue:#0071e3;--soft:#edf5ff;--green:#19784a;--shadow:0 16px 45px #1d1d1f08}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif}
    main{max-width:860px;margin:0 auto;padding:56px 24px 64px}.eyebrow{margin:0 0 10px;color:var(--blue);font-size:12px;font-weight:700;letter-spacing:2px}h1{font-size:clamp(29px,5vw,42px);line-height:1.2;letter-spacing:-1px;margin:0 0 14px}h2{font-size:19px;margin:0 0 18px}.lead{color:var(--muted);margin:0 0 32px}
    .card{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:26px;box-shadow:var(--shadow);margin-bottom:18px}.row{display:flex;gap:12px;align-items:center;flex-wrap:wrap}.field{flex:1;min-width:220px}label{display:block;font-weight:600;margin-bottom:8px}input{width:100%;min-height:48px;border:1px solid var(--line);background:var(--bg);color:var(--fg);border-radius:11px;padding:12px 14px;font:inherit;outline:none}input:focus{border-color:var(--blue);box-shadow:0 0 0 3px #0071e31a}
    button,.link{min-height:46px;padding:11px 18px;border-radius:11px;font:600 14px/1.5 inherit;cursor:pointer;border:1px solid transparent;background:var(--blue);color:white}button.secondary{background:var(--soft);color:var(--blue)}button.ghost{background:transparent;color:var(--fg);border-color:var(--line)}button:disabled{opacity:.42;cursor:not-allowed}button:focus-visible,a:focus-visible{outline:3px solid #0071e380;outline-offset:3px}
    .hint{font-size:12px;color:var(--muted);margin:12px 0 0}.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:0 0 24px}.stat{border-radius:12px;padding:15px;background:var(--bg)}.stat small{display:block;color:var(--muted);font-size:12px}.stat strong{display:block;margin-top:5px;font-size:16px}.good{color:var(--green)}.divider{height:1px;background:var(--line);margin:24px 0}.notice{min-height:46px;padding:13px 16px;margin-bottom:18px;background:var(--soft);border-radius:12px;color:var(--blue);white-space:pre-wrap;font-size:14px}.notice.error{background:#fff0ef;color:#ac2f24}.notice[hidden]{display:none}.footer{color:var(--muted);font-size:12px;text-align:center;padding-top:14px}a{color:var(--blue);text-decoration:none}.period{font-size:12px;color:var(--muted);margin:18px 0 0}.pill{display:inline-block;margin-left:8px;border-radius:20px;background:var(--soft);color:var(--blue);padding:3px 10px;font-size:11px;vertical-align:middle}
    @media(prefers-color-scheme:dark){:root{--bg:#161618;--card:#212124;--fg:#f5f5f7;--muted:#9b9ba4;--line:#36363c;--blue:#58a6ff;--soft:#182f4b;--green:#66cf98;--shadow:none}.notice.error{background:#3b211f;color:#ffafa5}button{background:#1680e8;color:#fff}}
    @media(max-width:560px){main{padding:32px 16px}.card{padding:22px 18px}.stats{grid-template-columns:1fr}.row>button{flex:1}.field{min-width:100%}.stat{display:flex;justify-content:space-between;align-items:center}.stat strong{margin:0}}
  </style>
</head>
<body>
<main>
  <p class="eyebrow">U30 PRO / MIHOMO</p>
  <h1>订阅与网络，简单掌控。</h1>
  <p class="lead">只更新节点，不覆盖路由规则。订阅通过检查后，再开启透明代理。</p>
  <div id="notice" class="notice" role="status" aria-live="polite" hidden></div>
  <section class="card" aria-labelledby="auth-title">
    <h2 id="auth-title">管理密钥 <span class="pill" id="auth-state">未连接</span></h2>
    <form id="auth-form" class="row" autocomplete="off">
      <div class="field"><label for="key">Mihomo API 密钥</label><input id="key" type="password" autocomplete="new-password" placeholder="输入管理密钥" spellcheck="false" autocapitalize="off" required></div>
      <button type="submit" id="connect">连接</button>
      <button type="button" class="ghost" id="forget" disabled>清除密钥</button>
    </form>
    <p class="hint">密钥仅保留在此页面的内存中；不写入浏览器存储。关闭或刷新页面后需重新输入。</p>
  </section>
  <section class="card" aria-labelledby="subscription-title">
    <h2 id="subscription-title">订阅管理</h2>
    <div class="stats">
      <div class="stat"><small>订阅地址</small><strong id="configured">等待连接</strong></div>
      <div class="stat"><small>节点配置</small><strong id="valid">等待连接</strong></div>
      <div class="stat"><small>透明代理</small><strong id="enabled">等待连接</strong></div>
    </div>
    <form id="subscription-form" autocomplete="off">
      <label for="url">HTTPS / Clash YAML 订阅</label>
      <input id="url" type="password" autocomplete="new-password" placeholder="粘贴 https:// 开头的订阅地址" spellcheck="false" autocapitalize="off" maxlength="8192" aria-describedby="url-hint">
      <p id="url-hint" class="hint">支持标准 Clash / Mihomo 节点 YAML（含 proxies 字段），以及包含该字段的完整配置。不使用第三方订阅转换。页面不回显已保存的地址。</p>
      <div class="row" style="margin-top:18px">
        <button type="submit" id="save" disabled>保存并更新</button>
        <button type="button" class="secondary" id="refresh" disabled>更新现有订阅</button>
        <button type="button" class="ghost" id="status" disabled>刷新状态</button>
      </div>
    </form>
    <p class="period">自动检查间隔：每 3600 秒（1 小时）。开机服务：<span id="autostart">—</span>。最近结果：<span id="last">—</span></p>
    <div class="divider"></div>
    <div class="row">
      <button type="button" id="enable" disabled>开启透明代理</button>
      <button type="button" class="ghost" id="disable" disabled>暂停 · 恢复直连</button>
      <a href="http://192.168.0.1:9090/ui/" target="_blank" rel="noopener noreferrer">打开节点面板 ↗</a>
    </div>
    <p class="hint">下载、格式校验或核心加载失败时，保留之前的订阅与节点。没有有效订阅时，设备继续直连。</p>
  </section>
  <p class="footer">仅供当前局域网使用 · 此管理端口使用 HTTP，请在可信 Wi-Fi 中操作。</p>
</main>
<script>
(() => {
  'use strict';
  const el = id => document.getElementById(id);
  let authKey = '', connected = false, busy = false, state = null;
  const errors = {
    authentication_required:'管理密钥不匹配，请重新输入。',lan_only:'请从设备局域网访问。',
    invalid_host:'请使用 192.168.0.1:9091 打开页面。',invalid_origin:'请求来源不匹配。',
    https_url_required:'请输入有效的 HTTPS 订阅地址。',not_configured:'尚未保存订阅，请先粘贴地址。',
    update_busy:'另一项更新正在运行，请稍后再试。',valid_clash_yaml_required:'订阅需要包含有效且非空的 Clash / Mihomo 节点 YAML；现有配置已保留。',
    core_update_failed_previous_restored:'核心未接受新节点，之前的节点与地址已恢复。',
    previous_files_restored_transparency_paused:'之前的节点文件与订阅地址已恢复；核心重载未通过，透明代理已暂停，请检查核心状态。',
    recovery_requires_attention:'之前的更新需要检查恢复状态，请联系管理人员。',
    update_failed_previous_retained:'更新未通过，请检查订阅连接、证书和格式；之前的配置已保留。',
    valid_subscription_required:'请先保存并验证有效订阅。',enable_failed:'透明代理开启失败，请检查设备运行状态。',
    disable_failed:'暂停操作未通过，请刷新状态确认。',body_too_large:'订阅地址长度应不超过 8192 字节。'
  };
  const lastLabels = {committed:'更新成功',download_failed:'下载或 TLS 校验失败',format_rejected:'订阅格式未通过',test_failed:'配置校验未通过',api_failed:'核心加载未通过',invalid_url:'地址格式未通过',not_configured:'尚未配置',busy:'正在更新',recovery_failed:'恢复待检查',recovery_api_failed:'文件已恢复，透明已暂停',none:'尚无记录'};
  function notice(text, error = false) { el('notice').textContent=text; el('notice').classList.toggle('error',error); el('notice').hidden=false; }
  function controls() {
    const unlocked=connected&&!busy;
    el('connect').disabled=busy;
    el('forget').disabled=!authKey||busy;
    for (const id of ['save','status']) el(id).disabled=!unlocked;
    el('refresh').disabled=!unlocked||!state?.configured;
    el('enable').disabled=!unlocked||!state?.valid||!!state?.enabled;
    el('disable').disabled=!unlocked||!state?.enabled;
    el('auth-state').textContent=connected?'已连接':'未连接';
  }
  function render(data) {
    state=data;
    el('configured').textContent=data.configured?'已配置（地址已隐藏）':'尚未配置';
    el('valid').textContent=data.valid?'已通过校验':'等待有效订阅';
    el('enabled').textContent=data.enabled?'已开启':'直连模式';
    el('valid').classList.toggle('good',!!data.valid);
    el('enabled').classList.toggle('good',!!data.enabled);
    el('last').textContent=lastLabels[data.last_result]||'尚无记录';
    el('autostart').textContent=data.autostart?'已启用':'未启用';
    controls();
  }
  async function api(action, body) {
    const options={method:body===undefined?'GET':'POST',cache:'no-store',credentials:'omit',redirect:'error',headers:{Authorization:'Bearer '+authKey}};
    if(body!==undefined){options.headers['Content-Type']='text/plain;charset=UTF-8';options.body=body;}
    const response=await fetch('/cgi-bin/manage.cgi?'+action,options);
    let data;
    try { data=await response.json(); } catch { throw new Error('管理服务响应异常，请检查服务状态。'); }
    if(!response.ok||!data.ok){
      if(response.status===401){authKey='';connected=false;state=null;el('key').value='';controls();}
      throw new Error(errors[data.error]||'操作未通过，请刷新状态后再试。');
    }
    return data;
  }
  async function run(task) {
    if(busy)return;
    busy=true;controls();
    try { await task(); } catch(error) { notice(error.message||'连接中断，请刷新状态确认。',true); }
    finally { busy=false;controls(); }
  }
  el('auth-form').addEventListener('submit',event=>{
    event.preventDefault();
    const entered=el('key').value.trim();el('key').value='';
    if(!entered)return;
    authKey=entered;
    run(async()=>{const data=await api('status');connected=true;render(data);notice('已连接。密钥仅保留在当前页面内存。');});
  });
  el('forget').addEventListener('click',()=>{
    authKey='';connected=false;state=null;el('key').value='';el('url').value='';
    for(const id of ['configured','valid','enabled'])el(id).textContent='等待连接';
    el('last').textContent='—';el('autostart').textContent='—';controls();notice('当前页面的密钥已清除。');
  });
  el('subscription-form').addEventListener('submit',event=>{
    event.preventDefault();let input=el('url').value.trim();el('url').value='';
    if(!input.startsWith('https://')){notice(errors.https_url_required,true);return;}
    if(new TextEncoder().encode(input).length>8192){notice(errors.body_too_large,true);return;}
    run(async()=>{notice('正在下载并验证订阅，请稍候…');await api('update',input);input='';render(await api('status'));notice('订阅已更新并加载。需要接管局域网流量时，请点击“开启透明代理”。');});
  });
  el('refresh').addEventListener('click',()=>run(async()=>{
    notice('正在更新现有订阅，请稍候…');await api('update','');render(await api('status'));notice('现有订阅已更新。');
  }));
  el('status').addEventListener('click',()=>run(async()=>{render(await api('status'));notice('状态已刷新。');}));
  el('enable').addEventListener('click',()=>run(async()=>{await api('enable','');render(await api('status'));notice('透明代理已开启。可前往节点面板选择节点。');}));
  el('disable').addEventListener('click',()=>run(async()=>{await api('disable','');render(await api('status'));notice('透明代理已暂停，局域网恢复直连。');}));
  window.addEventListener('pagehide',()=>{authKey='';el('key').value='';el('url').value='';});
  controls();
})();
</script>
</body>
</html>
U30_PUBLIC_ADMIN_HTML_EOF
cat > "$S/manage.cgi" <<'U30_PUBLIC_MANAGE_CGI_EOF'
#!/system/bin/sh
# BusyBox httpd CGI, bound by the controller to 192.168.0.1:9091 only.
set -u
umask 077
export LC_ALL=C
BASE=/data/adb/u30proxy
BB=/data/adb/magisk/busybox
TMP=

reply() {
    printf 'Status: %s\r\nContent-Type: application/json; charset=utf-8\r\n' "$1"
    printf 'Cache-Control: no-store\r\nPragma: no-cache\r\nX-Content-Type-Options: nosniff\r\n'
    printf 'X-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\n'
    printf 'Content-Security-Policy: default-src '\''none'\''; frame-ancestors '\''none'\''\r\n\r\n'
    printf '%s\n' "$2"
    exit 0
}

cleanup() { [ -n "$TMP" ] && "$BB" rm -rf "$TMP"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# No CORS header and an exact Host/Origin gate prevent cross-site UI requests.
case "${REMOTE_ADDR:-}" in 192.168.0.*) ;; *) reply '403 Forbidden' '{"ok":false,"error":"lan_only"}' ;; esac
case "${HTTP_HOST:-}" in 192.168.0.1:9091) ;; *) reply '403 Forbidden' '{"ok":false,"error":"invalid_host"}' ;; esac
case "${HTTP_ORIGIN:-}" in ''|http://192.168.0.1:9091) ;; *) reply '403 Forbidden' '{"ok":false,"error":"invalid_origin"}' ;; esac

key=$("$BB" cat "$BASE/secret/admin.secret" 2>/dev/null || :)
case "$key" in ''|*[!A-Za-z0-9._~@-]*) reply '503 Service Unavailable' '{"ok":false,"error":"key_unavailable"}' ;; esac
if [ "${HTTP_AUTHORIZATION:-}" != "Bearer $key" ]; then
    unset key
    reply '401 Unauthorized' '{"ok":false,"error":"authentication_required"}'
fi
unset key HTTP_AUTHORIZATION

status_body() {
    configured=false; valid=false; enabled=false; autostart=false
    [ -s "$BASE/secret/subscription.url" ] && configured=true
    [ -e "$BASE/run/subscription.valid" ] && valid=true
    [ -e "$BASE/run/transparent" ] && enabled=true
    [ -e "$BASE/run/autostart" ] && autostart=true
    last=$("$BB" cat "$BASE/run/subscription.last" 2>/dev/null || :)
    case "$last" in
        committed|download_failed|format_rejected|test_failed|api_failed|invalid_url|not_configured|busy|recovery_failed|recovery_api_failed) ;;
        *) last=none ;;
    esac
    printf '{"ok":true,"configured":%s,"valid":%s,"enabled":%s,"autostart":%s,"interval_seconds":3600,"last_result":"%s"}' \
        "$configured" "$valid" "$enabled" "$autostart" "$last"
}

case "${REQUEST_METHOD:-}" in
    GET)
        [ "${QUERY_STRING:-}" = status ] || reply '404 Not Found' '{"ok":false,"error":"unknown_action"}'
        reply '200 OK' "$(status_body)"
        ;;
    POST) ;;
    *) reply '405 Method Not Allowed' '{"ok":false,"error":"method_not_allowed"}' ;;
esac

length=${CONTENT_LENGTH:-0}
case "$length" in ''|*[!0-9]*) reply '411 Length Required' '{"ok":false,"error":"length_required"}' ;; esac
# Cap the textual length before shell arithmetic, including leading-zero input.
[ "${#length}" -le 5 ] || reply '413 Payload Too Large' '{"ok":false,"error":"body_too_large"}'
length=$(printf '%s' "$length" | "$BB" sed 's/^0*//')
[ -n "$length" ] || length=0
[ "$length" -le 8192 ] || reply '413 Payload Too Large' '{"ok":false,"error":"body_too_large"}'
case "${CONTENT_TYPE:-}" in text/plain|text/plain\;*) ;; *) reply '415 Unsupported Media Type' '{"ok":false,"error":"plain_text_required"}' ;; esac

case "${QUERY_STRING:-}" in
    update)
        TMP=$("$BB" mktemp -d "$BASE/run/cgi.XXXXXX") || reply '503 Service Unavailable' '{"ok":false,"error":"temporary_storage_failed"}'
        if [ "$length" -gt 0 ]; then
            "$BB" dd bs=1 count="$length" of="$TMP/body" 2>/dev/null || reply '400 Bad Request' '{"ok":false,"error":"invalid_body"}'
            actual=$("$BB" wc -c < "$TMP/body")
            [ "$actual" -eq "$length" ] || reply '400 Bad Request' '{"ok":false,"error":"incomplete_body"}'
            "$BASE/update.sh" set < "$TMP/body" > "$TMP/result" 2>/dev/null
        else
            "$BASE/update.sh" refresh > "$TMP/result" 2>/dev/null
        fi
        rc=$?
        if [ "$rc" = 0 ]; then
            reply '200 OK' '{"ok":true,"result":"updated","message":"Subscription validated and loaded; previous data is retained on failure."}'
        fi
        result=$("$BB" head -n 1 "$TMP/result" 2>/dev/null || :)
        case "$result" in
            busy) reply '409 Conflict' '{"ok":false,"error":"update_busy"}' ;;
            not_configured) reply '400 Bad Request' '{"ok":false,"error":"not_configured"}' ;;
            invalid_url) reply '400 Bad Request' '{"ok":false,"error":"https_url_required"}' ;;
            format_rejected|test_failed) reply '422 Unprocessable Entity' '{"ok":false,"error":"valid_clash_yaml_required"}' ;;
            api_failed) reply '503 Service Unavailable' '{"ok":false,"error":"core_update_failed_previous_restored"}' ;;
            recovery_api_failed) reply '503 Service Unavailable' '{"ok":false,"error":"previous_files_restored_transparency_paused"}' ;;
            recovery_failed) reply '503 Service Unavailable' '{"ok":false,"error":"recovery_requires_attention"}' ;;
            *) reply '502 Bad Gateway' '{"ok":false,"error":"update_failed_previous_retained"}' ;;
        esac
        ;;
    enable)
        [ "$length" = 0 ] || reply '400 Bad Request' '{"ok":false,"error":"empty_body_required"}'
        [ -e "$BASE/run/subscription.valid" ] || reply '409 Conflict' '{"ok":false,"error":"valid_subscription_required"}'
        "$BASE/control.sh" enable >/dev/null 2>&1 || reply '503 Service Unavailable' '{"ok":false,"error":"enable_failed"}'
        reply '200 OK' '{"ok":true,"result":"enabled"}'
        ;;
    disable)
        [ "$length" = 0 ] || reply '400 Bad Request' '{"ok":false,"error":"empty_body_required"}'
        "$BASE/control.sh" disable >/dev/null 2>&1 || reply '503 Service Unavailable' '{"ok":false,"error":"disable_failed"}'
        reply '200 OK' '{"ok":true,"result":"disabled"}'
        ;;
    *) reply '404 Not Found' '{"ok":false,"error":"unknown_action"}' ;;
esac
U30_PUBLIC_MANAGE_CGI_EOF
cat > "$S/u30proxy.sh" <<'U30_PUBLIC_U30PROXY_SH_EOF'
#!/system/bin/sh
# U30 proxy boot entry. No other Magisk services are modified.
B=/data/adb/u30proxy
while [ -f "$B/run/autostart" ]; do
    /system/bin/sh "$B/control.sh" boot >/dev/null 2>&1 && exit 0
    sleep 10
done
U30_PUBLIC_U30PROXY_SH_EOF
cat > "$S/u30-subscription.js" <<'U30_PUBLIC_U30_SUBSCRIPTION_JS_EOF'
(() => {
  function addEntry() {
    if (document.getElementById('u30-subscription-entry')) return;
    const a = document.createElement('a');
    a.id = 'u30-subscription-entry';
    a.textContent = '订阅管理';
    a.href = 'http://192.168.0.1:9091/';
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    a.style.cssText = 'position:fixed;right:20px;bottom:20px;z-index:10000;padding:12px 20px;border-radius:14px;background:#0071e3;color:#fff;text-decoration:none;font:600 14px/20px system-ui;box-shadow:0 6px 24px #0003;min-height:44px;box-sizing:border-box';
    document.body.appendChild(a);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', addEntry); else addEntry();
})();
U30_PUBLIC_U30_SUBSCRIPTION_JS_EOF
cat > "$S/config.template.yaml" <<'U30_PUBLIC_CONFIG_TEMPLATE_YAML_EOF'
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
cat > "$S/region-jp.yaml" <<'U30_PUBLIC_REGION_JP_YAML_EOF'
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
cat > "$S/region-hk.yaml" <<'U30_PUBLIC_REGION_HK_YAML_EOF'
# TVB News: platform-owned domains, not shared CDN suffixes.
payload:
  - '+.tvb.com'
U30_PUBLIC_REGION_HK_YAML_EOF
cat > "$S/region-tw.yaml" <<'U30_PUBLIC_REGION_TW_YAML_EOF'
# Bahamut Anime: Taiwan; dedicated CDN hosts only.
payload:
  - '+.gamer.com.tw'
  - '+.bahamut.com.tw'
  - 'bahamut.akamaized.net'
  - 'gamer-cds.cdn.hinet.net'
  - 'gamer2-cds.cdn.hinet.net'
U30_PUBLIC_REGION_TW_YAML_EOF
cat > "$S/region-us.yaml" <<'U30_PUBLIC_REGION_US_YAML_EOF'
payload: []
U30_PUBLIC_REGION_US_YAML_EOF
cat > "$S/region-sg.yaml" <<'U30_PUBLIC_REGION_SG_YAML_EOF'
payload: []
U30_PUBLIC_REGION_SG_YAML_EOF
cat > "$S/region-kr.yaml" <<'U30_PUBLIC_REGION_KR_YAML_EOF'
payload: []
U30_PUBLIC_REGION_KR_YAML_EOF
cat > "$S/capabilities.sh" <<'U30_PUBLIC_CAPABILITIES_SH_EOF'
#!/system/bin/sh
set -e
cleanup() {
iptables -w 5 -t mangle -F U30P_CAP 2>/dev/null || :
iptables -w 5 -t mangle -X U30P_CAP 2>/dev/null || :
ip6tables -w 5 -t mangle -F U30P_CAP 2>/dev/null || :
ip6tables -w 5 -t mangle -X U30P_CAP 2>/dev/null || :
}
trap cleanup EXIT HUP INT TERM
iptables -w 5 -t mangle -N U30P_CAP
iptables -w 5 -t mangle -A U30P_CAP -p tcp -j TPROXY --on-port 7893 --tproxy-mark 0x40000000/0x40000000
iptables -w 5 -t mangle -A U30P_CAP -p udp -j TPROXY --on-port 7893 --tproxy-mark 0x40000000/0x40000000
echo 'IPV4_TCP_UDP_TPROXY_KERNEL_ACCEPTED'
ip6tables -w 5 -t mangle -N U30P_CAP
ip6tables -w 5 -t mangle -A U30P_CAP -p tcp -j TPROXY --on-port 7893 --tproxy-mark 0x40000000/0x40000000
ip6tables -w 5 -t mangle -A U30P_CAP -p udp -j TPROXY --on-port 7893 --tproxy-mark 0x40000000/0x40000000
echo 'IPV6_TCP_UDP_TPROXY_KERNEL_ACCEPTED'
cleanup
echo 'CAPABILITY_TEST_CHAINS_REMOVED'
U30_PUBLIC_CAPABILITIES_SH_EOF
cat > "$S/prepare.sh" <<'U30_PUBLIC_PREPARE_SH_EOF'
#!/system/bin/sh
set -e
umask 077
B=/data/adb/u30proxy
S=${U30_STAGE:?}
test ! -e "$B" || { echo 'BASE_ALREADY_EXISTS_ABORT'; exit 2; }
mkdir -p "$B/bin" "$B/mihomo/providers" "$B/mihomo/rules" "$B/mihomo/ui" "$B/admin/cgi-bin" "$B/run" "$B/secret"
cp "$S/mihomo" "$B/bin/mihomo"
chmod 700 "$B/bin/mihomo"
cp "$S"/*.mrs "$B/mihomo/rules/"
printf 'payload: []\n' > "$B/mihomo/rules/custom-direct.yaml"
printf 'payload: []\n' > "$B/mihomo/rules/custom-proxy.yaml"
for REGION in jp hk tw us sg kr; do
  cp "$S/region-$REGION.yaml" "$B/mihomo/rules/region-$REGION.yaml"
done
printf 'proxies:\n  - name: subscription-direct\n    type: direct\n' > "$B/mihomo/providers/subscription.yaml"
/data/adb/magisk/busybox tar xzf "$S/ui.tgz" -C "$B/mihomo/ui"
API_SECRET=$(/data/adb/magisk/busybox od -An -tx1 -N32 /dev/urandom | tr -d ' \n')
test ${#API_SECRET} = 64
printf '%s\n' "$API_SECRET" > "$B/secret/admin.secret"
sed "s/@API_SECRET@/$API_SECRET/" "$S/config.template.yaml" > "$B/mihomo/config.yaml"
chmod 600 "$B/secret/admin.secret" "$B/mihomo/config.yaml" "$B/mihomo/providers/subscription.yaml"
sha256sum "$B/bin/mihomo" "$B/mihomo/rules"/* > "$B/run/installed.sha256"
"$B/bin/mihomo" -v
"$B/bin/mihomo" -t -d "$B/mihomo"
echo 'CORE_FILES_AND_CONFIG_VALIDATED'
U30_PUBLIC_PREPARE_SH_EOF
cat > "$S/install-services.sh" <<'U30_PUBLIC_INSTALL_SERVICES_SH_EOF'
#!/system/bin/sh
set -e
umask 077
B=/data/adb/u30proxy
S=${U30_STAGE:?}
cp "$S/control.sh" "$B/control.sh"
cp "$S/update.sh" "$B/update.sh"
cp "$S/admin.html" "$B/admin/index.html"
cp "$S/manage.cgi" "$B/admin/cgi-bin/manage.cgi"
chmod 700 "$B/control.sh" "$B/update.sh" "$B/admin/cgi-bin/manage.cgi"
chmod 600 "$B/admin/index.html"
cp "$S/u30-subscription.js" "$B/mihomo/ui/u30-subscription.js"
chmod 600 "$B/mihomo/ui/u30-subscription.js"
if ! grep -F 'u30-subscription.js' "$B/mihomo/ui/index.html" >/dev/null; then
    cp "$B/mihomo/ui/index.html" "$B/run/ui-index.original.html"
    sed 's#</body>#<script src="./u30-subscription.js"></script></body>#' "$B/mihomo/ui/index.html" > "$B/mihomo/ui/index.html.new"
    grep -F 'u30-subscription.js' "$B/mihomo/ui/index.html.new" >/dev/null
    chmod 600 "$B/mihomo/ui/index.html.new"
    mv -f "$B/mihomo/ui/index.html.new" "$B/mihomo/ui/index.html"
fi
/system/bin/sh -n "$B/control.sh"
/system/bin/sh -n "$B/update.sh"
/system/bin/sh -n "$B/admin/cgi-bin/manage.cgi"
cp "$S/u30proxy.sh" /data/adb/service.d/u30proxy.sh
chmod 700 /data/adb/service.d/u30proxy.sh
touch "$B/run/autostart"
"$B/control.sh" start
"$B/control.sh" status
echo 'SERVICES_STARTED_WITHOUT_UNCONFIGURED_TRANSPARENT_CAPTURE'
U30_PUBLIC_INSTALL_SERVICES_SH_EOF

for f in "$S"/*.sh "$S/manage.cgi"; do /system/bin/sh -n "$f" || fail EMBEDDED_SHELL_SYNTAX_FAILED; done
for family in iptables ip6tables; do
    "$family" -t mangle -S U30P_CAP >/dev/null 2>&1 && fail CAPABILITY_CHAIN_CONFLICT_PRESERVED || :
done
probe_cleanup() {
    iptables -w 5 -t mangle -F U30P_CAP 2>/dev/null || :
    iptables -w 5 -t mangle -X U30P_CAP 2>/dev/null || :
    ip6tables -w 5 -t mangle -F U30P_CAP 2>/dev/null || :
    ip6tables -w 5 -t mangle -X U30P_CAP 2>/dev/null || :
}
PROBE_OWNED=1
/system/bin/sh "$S/capabilities.sh" > "$S/capabilities.log" 2>&1 || fail TPROXY_KERNEL_CAPABILITY_FAILED
for family in iptables ip6tables; do
    "$family" -w 5 -t mangle -N U30P_CAP || { probe_cleanup; fail SOCKET_CAPABILITY_CREATE_FAILED; }
    "$family" -w 5 -t mangle -A U30P_CAP -p tcp -m socket --transparent --nowildcard -j ACCEPT || { probe_cleanup; fail SOCKET_KERNEL_CAPABILITY_FAILED; }
    "$family" -w 5 -t mangle -A U30P_CAP -p udp -m socket --transparent --nowildcard -j ACCEPT || { probe_cleanup; fail SOCKET_KERNEL_CAPABILITY_FAILED; }
done
probe_cleanup
PROBE_OWNED=0
fetch() {
    target=$1; expected=$2; url=$3
    "$CURL" --disable --fail --show-error --location --retry 2 --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' --output "$target.part" "$url" || fail OFFICIAL_HTTPS_DOWNLOAD_FAILED
    "$BB" chmod 600 "$target.part"
    hash_ok "$target.part" "$expected" || fail OFFICIAL_ASSET_HASH_MISMATCH
    "$BB" mv "$target.part" "$target"
}
if hash_ok /data/local/tmp/u30-stage/mihomo "$CORE_SHA"; then
    "$BB" cp /data/local/tmp/u30-stage/mihomo "$S/mihomo"
else
    fetch "$S/mihomo.gz" 42b1f2be8702484d3ae6238daab392622f54bd0d264966700f1f28f52596e326 https://github.com/MetaCubeX/mihomo/releases/download/v1.19.32/mihomo-android-arm64-v8-v1.19.32.gz
    "$BB" gzip -dc "$S/mihomo.gz" > "$S/mihomo"
fi
hash_ok "$S/mihomo" "$CORE_SHA" || fail CORE_DECOMPRESSED_HASH_MISMATCH
"$BB" chmod 700 "$S/mihomo"
fetch "$S/ui.tgz" 7bea3c8878cb15a4bd9ee58275045f41642e17667dbe1ae3ce27bf5e3e7dc99b https://github.com/MetaCubeX/metacubexd/releases/download/v1.270.6/compressed-dist.tgz
if hash_ok /data/local/tmp/u30-stage/geoip-cn.mrs d8573e8435f16116a4ba7ef7bfe914d9615e43a812eb2a348694ef21b20e0ed3; then
    "$BB" cp /data/local/tmp/u30-stage/geoip-cn.mrs "$S/geoip-cn.mrs"
else
    fetch "$S/geoip-cn.mrs" d8573e8435f16116a4ba7ef7bfe914d9615e43a812eb2a348694ef21b20e0ed3 https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/989c8194a8c01e8d85ab2c33aa7d8af3849d3393/geo/geoip/cn.mrs
fi
if hash_ok /data/local/tmp/u30-stage/geoip-private.mrs 076ea1da10b442f01c6fb3b86a66411727a15df69d70e8d600a8a458b07a8bb0; then
    "$BB" cp /data/local/tmp/u30-stage/geoip-private.mrs "$S/geoip-private.mrs"
else
    fetch "$S/geoip-private.mrs" 076ea1da10b442f01c6fb3b86a66411727a15df69d70e8d600a8a458b07a8bb0 https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/989c8194a8c01e8d85ab2c33aa7d8af3849d3393/geo/geoip/private.mrs
fi
if hash_ok /data/local/tmp/u30-stage/geosite-cn.mrs 2f7ccaf6ac344b22f2d3751ffcdd1e102f6cd698fb526c4c3eb4c0797505d75f; then
    "$BB" cp /data/local/tmp/u30-stage/geosite-cn.mrs "$S/geosite-cn.mrs"
else
    fetch "$S/geosite-cn.mrs" 2f7ccaf6ac344b22f2d3751ffcdd1e102f6cd698fb526c4c3eb4c0797505d75f https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/989c8194a8c01e8d85ab2c33aa7d8af3849d3393/geo/geosite/cn.mrs
fi
if hash_ok /data/local/tmp/u30-stage/geosite-private.mrs 0f9ba48d4d0b0d192a4e7c3548486dde05e5a92e6e58e8ea8c9cc302712a1420; then
    "$BB" cp /data/local/tmp/u30-stage/geosite-private.mrs "$S/geosite-private.mrs"
else
    fetch "$S/geosite-private.mrs" 0f9ba48d4d0b0d192a4e7c3548486dde05e5a92e6e58e8ea8c9cc302712a1420 https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/989c8194a8c01e8d85ab2c33aa7d8af3849d3393/geo/geosite/private.mrs
fi

"$BB" chmod 600 "$S"/*
"$BB" chmod 700 "$S/mihomo"
/system/bin/sh "$S/prepare.sh" > "$S/prepare.log" 2>&1 || fail FRESH_PREPARE_FAILED_ORIGINALS_PRESERVED
FRESH=1
/system/bin/sh "$S/install-services.sh" > "$S/install-services.log" 2>&1 || fail FRESH_SERVICES_FAILED_ORIGINALS_PRESERVED
/system/bin/sh "$BASE/control.sh" status > "$S/status.txt"
for state in core=running controller=authenticated-ready admin=running watchdog=running autostart=yes subscription=none transparent=off; do
    "$BB" grep -F -x "$state" "$S/status.txt" >/dev/null || fail FRESH_SERVICE_STATE_INVALID
done
cat > "$BACKUP/rollback.sh" <<'U30_FRESH_ROLLBACK_EOF'
#!/system/bin/sh
set -eu
[ "$(id -u)" = 0 ] || exit 1
/system/bin/sh /data/adb/u30proxy/control.sh rollback
/system/bin/sh /data/adb/u30proxy/control.sh status
U30_FRESH_ROLLBACK_EOF
"$BB" chmod 700 "$BACKUP/rollback.sh"
"$BB" cp "$S/capabilities.log" "$S/prepare.log" "$S/install-services.log" "$S/status.txt" "$BACKUP/"
"$BB" chmod 600 "$BACKUP"/*.log "$BACKUP/status.txt"
"$BB" cat "$S/status.txt"
printf 'U30_PLUGIN_OK: fresh services installed; capture stays off until a subscription is validated and enabled.\n'
printf 'Controller: http://192.168.0.1:9090/ui/\nSubscription manager: http://192.168.0.1:9091/\n'
printf 'Private key file: /data/adb/u30proxy/secret/admin.secret (root-only; value not printed)\n'
printf 'Root-only rollback: /system/bin/sh %s/rollback.sh\n' "$BACKUP"
FRESH=0
