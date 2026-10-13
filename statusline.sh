#!/usr/bin/env bash

# Portable second status line for the gpakosz .tmux framework.
#
# Renders system stats (disk, network, cpu, ram, battery) for
# `status-format[1]`.
#
# macOS 26 kernel-leak workaround: the OS leaks ~1KiB of wired kernel
# memory (data.kalloc.1024) for every script-executed-from-a-script.
# This script therefore execs compiled binaries only (tmux, awk, df,
# netstat, iostat, vm_stat, date, curl, jq) and inlines the logic of
# the tmux-cpu / tmux-network-speed plugin scripts.

style='#[fg=#8a8a8a,bg=#080808]'
tmuxopt() { tmux show-options -gqv "$1" 2>/dev/null; }

# --- data: compute values here ------------------------------------------------

battery_status="$(tmuxopt '@battery_status')"
battery_bar="$(tmuxopt '@battery_bar')"
battery_percentage="$(tmuxopt '@battery_percentage')"

disk="$(df -h / | awk 'NR==2 {print $4}')"

iface="$(tmuxopt '@network_speed_interface')"
[ -z "$iface" ] && iface=en0
read -r cur_rx cur_tx < <(netstat -bn -I "$iface" 2>/dev/null | awk '/<Link#/ {print $7, $10; exit}')
cur_rx="${cur_rx:-0}"; cur_tx="${cur_tx:-0}"
prev_rx="$(tmuxopt '@network_speed_rx')"; prev_rx="${prev_rx:-0}"
prev_tx="$(tmuxopt '@network_speed_tx')"; prev_tx="${prev_tx:-0}"
now="$(date +%s)"
lt_rx="$(tmuxopt '@network_speed_last_update_time_rx')"; lt_rx="${lt_rx:-0}"
lt_tx="$(tmuxopt '@network_speed_last_update_time_tx')"; lt_tx="${lt_tx:-0}"

fmt_speed() {
    awk -v b="$1" 'BEGIN {
        if      (b >= 1073741824) printf "%05.2f GB/s", b / 1073741824
        else if (b >= 1048576)    printf "%05.2f MB/s", b / 1048576
        else if (b >= 1024)       printf "%05.2f KB/s", b / 1024
        else                      printf "%05.2f B/s",  b
    }'
}

if [ "$((now - lt_tx))" -gt 0 ] && [ "$cur_rx" != "0" ]; then
    rx_bps=$(( (cur_rx - prev_rx) / (now - lt_rx) )); [ "$rx_bps" -lt 0 ] && rx_bps=0
    tx_bps=$(( (cur_tx - prev_tx) / (now - lt_tx) )); [ "$tx_bps" -lt 0 ] && tx_bps=0
    rx_speed="$(fmt_speed "$rx_bps")"
    tx_speed="$(fmt_speed "$tx_bps")"
    tmux set-option -gq '@network_speed_rx' "$cur_rx"
    tmux set-option -gq '@network_speed_tx' "$cur_tx"
    tmux set-option -gq '@network_speed_last_update_time_rx' "$now"
    tmux set-option -gq '@network_speed_last_update_time_tx' "$now"
    tmux set-option -gq '@network_speed_last_speed_rx' "$rx_speed"
    tmux set-option -gq '@network_speed_last_speed_tx' "$tx_speed"
else
    rx_bps=0; tx_bps=0
    rx_speed="$(tmuxopt '@network_speed_last_speed_rx')"
    tx_speed="$(tmuxopt '@network_speed_last_speed_tx')"
fi

dl_color="$(tmuxopt '@network_speed_download_color')"; dl_color="${dl_color:-#[fg=green]}"
up_color="$(tmuxopt '@network_speed_upload_color')";    up_color="${up_color:-#[fg=yellow]}"
hi_color="$(tmuxopt '@network_speed_high_color')";      hi_color="${hi_color:-#[fg=red]}"
threshold="$(tmuxopt '@network_speed_threshold')";      threshold="${threshold:-0}"
if [ "$threshold" -gt 0 ] 2>/dev/null; then
    thr_unit="$(tmuxopt '@network_speed_threshold_unit')"; thr_unit="${thr_unit:-MB/s}"
    thr_bytes="$(printf '%s %s' "$threshold" "$thr_unit" | awk '{
        m = ($2 == "GB/s") ? 1073741824 : ($2 == "MB/s") ? 1048576 : ($2 == "KB/s") ? 1024 : 1
        printf "%d", $1 * m
    }')"
    [ "$rx_bps" -ge "$thr_bytes" ] 2>/dev/null && dl_color="$hi_color"
    [ "$tx_bps" -ge "$thr_bytes" ] 2>/dev/null && up_color="$hi_color"
fi
network="${dl_color}↓ ${rx_speed}#[fg=default] ${up_color}↑ ${tx_speed}#[fg=default]"

cpu="$(LC_ALL=C iostat -c 2 disk0 2>/dev/null | LC_ALL=C awk '$6 ~ /^[0-9.]+$/ {idle=$6} END {if (idle != "") printf "%3.1f%%", 100 - idle}')"

ram="$(vm_stat | LC_ALL=C awk '
    /Pages active|Pages inactive|Pages speculative|Pages wired down|Pages occupied by compressor/ {t=$0; gsub(/[^0-9]/, "", t); u += t}
    /Pages purgeable|File-backed pages/ {t=$0; gsub(/[^0-9]/, "", t); c += t}
    /Pages free/ {t=$0; gsub(/[^0-9]/, "", t); f += t}
    END {printf "%3.1f%%", 100 * (u - c) / (u + f)}
')"

style_for() { # $1 = level, $2 = option prefix
    local color icon
    color="$(tmuxopt "@${2}_${1}_fg_color")"
    icon="$(tmuxopt "@${2}_${1}_icon")"
    case "$1" in
        high)   [ -z "$color" ] && color="#[fg=red]";    [ -z "$icon" ] && icon="≣" ;;
        medium) [ -z "$color" ] && color="#[fg=yellow]"; [ -z "$icon" ] && icon="≡" ;;
        low)    [ -z "$color" ] && color="#[fg=green]";  [ -z "$icon" ] && icon="=" ;;
    esac
    printf '%s\n%s' "$color" "$icon"
}

cpu_med="$(tmuxopt '@cpu_medium_thresh')"; cpu_med="${cpu_med:-30}"
cpu_hi="$(tmuxopt '@cpu_high_thresh')";    cpu_hi="${cpu_hi:-80}"
cpu_lvl="$(printf '%s %s %s' "$cpu" "$cpu_med" "$cpu_hi" | awk '{gsub(/%/,"",$1); print ($1>$3)?"high":($1>$2)?"medium":"low"}')"
cpu_style="$(style_for "$cpu_lvl" cpu)"
cpu_color="${cpu_style%%$'\n'*}"; cpu_icon="${cpu_style#*$'\n'}"

ram_med="$(tmuxopt '@ram_medium_thresh')"; ram_med="${ram_med:-30}"
ram_hi="$(tmuxopt '@ram_high_thresh')";    ram_hi="${ram_hi:-80}"
ram_lvl="$(printf '%s %s %s' "$ram" "$ram_med" "$ram_hi" | awk '{print ($1>$3)?"high":($1>$2)?"medium":"low"}')"
ram_style="$(style_for "$ram_lvl" ram)"
ram_color="${ram_style%%$'\n'*}"; ram_icon="${ram_style#*$'\n'}"

datetime="📅 $(date '+%m/%d %H:%M')"

ollama_usage="$(tmuxopt '@ollama_usage')"
ollama_ts="$(tmuxopt '@ollama_usage_ts')"
now="$(date +%s)"
# Throttle strictly by timestamp (once per 60s) regardless of last result,
# so a failed request never causes a 10s retry loop (ollama.com rate limit).
if [ $((now - ${ollama_ts:-0})) -gt 60 ] && [ -n "$OLLAMA_API_KEY" ]; then
    fresh="$(curl -fsS -m 8 -H "Authorization: $OLLAMA_API_KEY" https://ollama.com/api/balance 2>/dev/null | jq -c '{
        session: .included.session.remaining_percent,
        weekly: .included.weekly.remaining_percent,
        session_resets: (.included.session.resets_at | fromdateiso8601),
        weekly_resets: (.included.weekly.resets_at | fromdateiso8601)
    }')"
    tmux set-option -gq '@ollama_usage_ts' "$now"
    if [ -n "$fresh" ]; then
        ollama_usage="$fresh"
        tmux set-option -gq '@ollama_usage' "$ollama_usage"
    fi
fi

fmt_reset() { # $1 = reset epoch -> "2.3h", "4d 21h", "45m"
    awk -v now="$now" -v t="$1" 'BEGIN {
        d = t - now; if (d < 0) d = 0
        if      (d >= 86400) printf "%dd %dh", d / 86400, (d % 86400) / 3600
        else if (d >= 3600)  {h = int(d / 360 + 0.5) / 10; if (h == int(h)) printf "%dh", h; else printf "%.1fh", h}
        else if (d >= 60)    printf "%dm", d / 60
        else                 printf "<1m"
    }'
}

ollama_5h=""; ollama_7d=""; ollama_5h_reset=""; ollama_7d_reset=""
if [ -n "$ollama_usage" ]; then
    ollama_5h="$(printf '%s' "$ollama_usage" | jq -r '.session')"
    ollama_7d="$(printf '%s' "$ollama_usage" | jq -r '.weekly')"
    sr="$(printf '%s' "$ollama_usage" | jq -r '.session_resets // empty')"
    wr="$(printf '%s' "$ollama_usage" | jq -r '.weekly_resets // empty')"
    [ -n "$sr" ] && ollama_5h_reset="$(fmt_reset "$sr")"
    [ -n "$wr" ] && ollama_7d_reset="$(fmt_reset "$wr")"
fi

moon="$(awk -v s="$(date +%s)" 'BEGIN {
    jd = 2440587.5 + s / 86400
    age = (jd - 2451550.1) % 29.53058867
    phase = age / 29.53058867
    if      (phase < 0.125) e = "\360\237\214\221"
    else if (phase < 0.250) e = "\360\237\214\222"
    else if (phase < 0.375) e = "\360\237\214\223"
    else if (phase < 0.500) e = "\360\237\214\224"
    else if (phase < 0.625) e = "\360\237\214\225"
    else if (phase < 0.750) e = "\360\237\214\226"
    else if (phase < 0.875) e = "\360\237\214\227"
    else                    e = "\360\237\214\230"
    print e
}')"

# --- segments: compose what to show -------------------------------------------

left_segments=()
right_segments=()

left_segments+=( "⛁ Disk: $disk" )
left_segments+=( "📶 $network" )
if [ -n "$ollama_5h" ]; then
    ollama_seg="🦙 5h: ${ollama_5h}%"
    [ -n "$ollama_5h_reset" ] && ollama_seg+=" (${ollama_5h_reset})"
    ollama_seg+=" · 7d: ${ollama_7d}%"
    [ -n "$ollama_7d_reset" ] && ollama_seg+=" (${ollama_7d_reset})"
    left_segments+=( "$ollama_seg" )
fi

battery=""
[ -n "$battery_status" ] && battery+="$battery_status "
[ -n "$battery_bar" ] && battery+="$battery_bar "
[ -n "$battery_percentage" ] && battery+="$battery_percentage"
[ -n "$battery" ] && right_segments+=( "$battery" )
right_segments+=( "${cpu_color}${cpu_icon}CPU: $cpu" )
right_segments+=( "${ram_color}${ram_icon}RAM: $ram" )
right_segments+=( "$datetime" )

right_segments+=( "$moon " )

# --- render: no need to touch below this line ----------------------------------

emit() { # $1 = alignment, $2 = separator, rest = segments
    local align="$1" sep="$2"
    shift 2
    printf '#[align=%s]' "$align"
    [ "$align" = left ] && printf ' '
    local first=1
    for seg in "$@"; do
        if [ "$first" -eq 1 ]; then
            first=0
        else
            printf '%s' "$sep"
        fi
        printf '%s%s' "$style" "$seg"
    done
}

emit left " | " "${left_segments[@]}"
emit right " | " "${right_segments[@]}"
