#!/system/bin/sh
# SysVer for Android
# A dependency-free, sourceable shell library for collecting device information.
#
# Public API:
#   . ./sysver.sh
#   sysver_collect            # emits a JSON object
#   sysver_value <field>      # emits one field as plain text
#
# The implementation uses Android system properties, procfs, toybox and POSIX
# utilities when available. Missing values are emitted as null/unknown rather
# than causing the caller to fail.

_sysver_trim() {
    # Trim leading and trailing whitespace without requiring sed extensions.
    printf '%s' "$1" | awk '{$1=$1; print}'
}

_sysver_prop() {
    if command -v getprop >/dev/null 2>&1; then
        getprop "$1" 2>/dev/null | tr -d '\r' | sed 's/^\[//; s/]$//'
    fi
}

_sysver_number() {
    case "$1" in
        ''|*[!0-9.\ -]*) return 1 ;;
        *) printf '%s' "$1" ;;
    esac
}

_sysver_cpu_model() {
    awk -F: '
        tolower($1) ~ /hardware|model name|processor/ {gsub(/^[ \t]+/, "", $2); if ($2 != "") {print $2; exit}}
    ' /proc/cpuinfo 2>/dev/null
}

_sysver_cpu_count() {
    awk '/^processor[ \t]*:/ {n++} END {if (n) print n}' /proc/cpuinfo 2>/dev/null
}

_sysver_cpu_frequency() {
    # Prefer the first policy frequency, then cpuinfo_max_freq (kHz).
    f=""
    for p in /sys/devices/system/cpu/cpufreq/policy*/cpuinfo_cur_freq \
             /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        if [ -r "$p" ]; then f=$(cat "$p" 2>/dev/null); [ -n "$f" ] && break; fi
    done
    if [ -z "$f" ]; then
        f=$(awk -F: '/^cpu MHz/ {gsub(/[ \t]/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
        [ -n "$f" ] && printf '%s MHz' "$f" && return
    fi
    case "$f" in
        '' ) return ;;
        *[!0-9]* ) printf '%s' "$f" ;;
        * ) awk -v k="$f" 'BEGIN {printf "%.0f MHz", k/1000}' ;;
    esac
}

_sysver_ips() {
    # ip(8) is present in current Android releases. Fall back to ifconfig.
    if command -v ip >/dev/null 2>&1; then
        ip -o addr show 2>/dev/null | awk '$3 == "inet" || $3 == "inet6" {sub(/\/.*/, "", $4); if ($4 !~ /^127\./ && $4 != "::1") print $4}' | paste -sd, -
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null | awk '/inet addr:/ {sub("addr:", "", $2); if ($2 !~ /^127\./) print $2} /inet / {if ($2 !~ /^127\./ && $2 != "::1") {sub(/\/.*/, "", $2); print $2}}' | paste -sd, -
    fi
}

_sysver_mem() {
    awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} /^MemFree:/ {f=$2} END {if (!a) a=f; if (t) {u=t-a; printf "%s|%s|%s|%.2f", t*1024, a*1024, u*1024, (u*100)/t}}' /proc/meminfo 2>/dev/null
}

_sysver_disk() {
    # /data is the primary writable system volume on Android; use / when it
    # is unavailable. POSIX df output is sufficient for toybox and busybox.
    mountpoint=/data
    [ -d "$mountpoint" ] || mountpoint=/
    df -P "$mountpoint" 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $2*1024 "|" $4*1024 "|" $5}'
}

_sysver_json_escape() {
    # Escape the JSON characters used by values returned from Android.
    printf '%s' "$1" | awk 'BEGIN {ORS=""} {gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\r/, "\\r"); gsub(/\t/, "\\t"); print}'
}

_sysver_json_string() {
    if [ -n "$1" ]; then printf '"%s"' "$(_sysver_json_escape "$1")"; else printf 'null'; fi
}

sysver_value() {
    key=$1
    case "$key" in
        android_version) _sysver_prop ro.build.version.release ;;
        kernel_version) uname -r 2>/dev/null ;;
        architecture) uname -m 2>/dev/null ;;
        processor_model) _sysver_cpu_model ;;
        physical_cpu_count) n=$(grep -c '^physical id' /proc/cpuinfo 2>/dev/null); [ "$n" -gt 0 ] 2>/dev/null && printf '%s\n' "$n" || printf '%s\n' "$(_sysver_cpu_count)" ;;
        logical_cpu_count) _sysver_cpu_count ;;
        cpu_frequency) _sysver_cpu_frequency ;;
        load_average) [ -r /proc/loadavg ] && awk '{print $1 "," $2 "," $3}' /proc/loadavg ;;
        java_version) java -version 2>&1 | sed -n '1{s/.*version "\([^"]*\)".*/\1/;p;}' ;;
        phone_name) n=$(_sysver_prop ro.product.model); [ -n "$n" ] && printf '%s\n' "$n" || _sysver_prop ro.product.name ;;
        ip_addresses) _sysver_ips ;;
        uptime_seconds) [ -r /proc/uptime ] && awk '{print $1}' /proc/uptime ;;
        boot_time) u=$(sysver_value uptime_seconds); now=$(date +%s 2>/dev/null); [ -n "$u" ] && [ -n "$now" ] && awk -v n="$now" -v u="$u" 'BEGIN {printf "%.0f", n-u}' ;;
        memory) _sysver_mem ;;
        disk) _sysver_disk ;;
        *) return 2 ;;
    esac
}

sysver_collect() {
    android_version=$(sysver_value android_version)
    kernel_version=$(sysver_value kernel_version)
    architecture=$(sysver_value architecture)
    processor_model=$(sysver_value processor_model)
    physical_cpu_count=$(sysver_value physical_cpu_count)
    logical_cpu_count=$(sysver_value logical_cpu_count)
    cpu_frequency=$(sysver_value cpu_frequency)
    load_average=$(sysver_value load_average)
    java_version=$(sysver_value java_version)
    phone_name=$(sysver_value phone_name)
    ip_addresses=$(sysver_value ip_addresses)
    uptime_seconds=$(sysver_value uptime_seconds)
    boot_time=$(sysver_value boot_time)
    memory=$(_sysver_mem); disk=$(_sysver_disk)

    mem_total=${memory%%|*}; mem_rest=${memory#*|}; mem_available=${mem_rest%%|*}; mem_rest=${mem_rest#*|}; mem_used=${mem_rest%%|*}; mem_percent=${mem_rest#*|}
    disk_capacity=${disk%%|*}; disk_rest=${disk#*|}; disk_free=${disk_rest%%|*}; disk_percent=${disk_rest#*|}
    printf '{"android_version":%s,"kernel_version":%s,"architecture":%s,"processor_model":%s,"physical_cpu_count":%s,"logical_cpu_count":%s,"cpu_frequency":%s,"load_average":%s,"java_version":%s,"phone_name":%s,"ip_addresses":%s,"uptime_seconds":%s,"boot_time":%s,"memory":{"total_bytes":%s,"available_bytes":%s,"used_bytes":%s,"usage_percent":%s},"disk":{"capacity_bytes":%s,"free_bytes":%s,"usage_percent":%s}}\n' \
      "$(_sysver_json_string "$android_version")" "$(_sysver_json_string "$kernel_version")" "$(_sysver_json_string "$architecture")" "$(_sysver_json_string "$processor_model")" \
      "${physical_cpu_count:-null}" "${logical_cpu_count:-null}" "$(_sysver_json_string "$cpu_frequency")" "$(_sysver_json_string "$load_average")" "$(_sysver_json_string "$java_version")" "$(_sysver_json_string "$phone_name")" \
      "$(_sysver_json_string "$ip_addresses")" "${uptime_seconds:-null}" "${boot_time:-null}" "${mem_total:-null}" "${mem_available:-null}" "${mem_used:-null}" "${mem_percent:-null}" "${disk_capacity:-null}" "${disk_free:-null}" "${disk_percent:-null}"
}

# Run as a command as well as a sourceable library.
[ "${0##*/}" = "sysver.sh" ] && sysver_collect
