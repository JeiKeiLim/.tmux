#!/usr/bin/env bash

# Portable second status line for the gpakosz .tmux framework.
#
# Renders system stats (disk, network, cpu, ram, battery) for
# `status-format[1]` using the tpm plugin scripts, resolving their
# location dynamically so this works on any machine that clones this
# repo (e.g. to ~/.tmux) with the same plugins installed.
#
# Usage in .tmux.conf.local:
#   set -g status 2
#   set -g status-format[1] "#(~/.tmux/statusline.sh)"
#
# To add new info: compute it in the "data" section, then append it to
# `left_segments` or `right_segments`. Done.

plugin_dir="${TMUX_PLUGIN_MANAGER_PATH:-}"
if [ -z "$plugin_dir" ] || [ ! -d "$plugin_dir" ]; then
    for d in "$(cd "$(dirname "$0")" && pwd)/plugins" "$HOME/.tmux/plugins"; do
        if [ -d "$d" ]; then
            plugin_dir="$d"
            break
        fi
    done
fi

if [ -z "$plugin_dir" ] || [ ! -d "$plugin_dir/tmux-cpu" ]; then
    printf '#[fg=#8a8a8a,bg=#080808]plugins not found (run Prefix + I)'
    exit 0
fi

style='#[fg=#8a8a8a,bg=#080808]'

# --- data: compute values here ------------------------------------------------

battery_status="$(tmux show-options -gqv '@battery_status')"
battery_bar="$(tmux show-options -gqv '@battery_bar')"
battery_percentage="$(tmux show-options -gqv '@battery_percentage')"

disk="$(df -h / | awk '{print $4}' | tail -n 1)"
network="$( "$plugin_dir/tmux-network-speed/network_speed.sh" 2>/dev/null )"
cpu_color="$( "$plugin_dir/tmux-cpu/scripts/cpu_fg_color.sh" )"
cpu_icon="$( "$plugin_dir/tmux-cpu/scripts/cpu_icon.sh" )"
cpu="$( "$plugin_dir/tmux-cpu/scripts/cpu_percentage.sh" )"
ram_color="$( "$plugin_dir/tmux-cpu/scripts/ram_fg_color.sh" )"
ram_icon="$( "$plugin_dir/tmux-cpu/scripts/ram_icon.sh" )"
ram="$( "$plugin_dir/tmux-cpu/scripts/ram_percentage.sh" )"
datetime="📅 $(date '+%m/%d %H:%M')"

ollama_usage="$(tmux show-options -gqv '@ollama_usage')"
ollama_ts="$(tmux show-options -gqv '@ollama_usage_ts')"
now="$(date +%s)"
if [ -z "$ollama_usage" ] || [ $((now - ${ollama_ts:-0})) -gt 300 ]; then
    if [ -n "$OLLAMA_API_KEY" ]; then
        ollama_usage="$(curl -fsS -m 5 -H "Authorization: $OLLAMA_API_KEY" https://ollama.com/api/usage 2>/dev/null | jq -c '{session: (.limits.session.usage * 1000 | round / 10), weekly: (.limits.weekly.usage * 1000 | round / 10)}')"
        tmux set-option -gq '@ollama_usage' "$ollama_usage"
        tmux set-option -gq '@ollama_usage_ts' "$now"
    fi
fi
ollama_5h=""; ollama_7d=""
if [ -n "$ollama_usage" ]; then
    ollama_5h="$(printf '%.1f' "$(printf '%s' "$ollama_usage" | jq -r '.session')")"
    ollama_7d="$(printf '%.1f' "$(printf '%s' "$ollama_usage" | jq -r '.weekly')")"
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
    left_segments+=( "🦙 5h: ${ollama_5h}% · 7d: ${ollama_7d}%" )
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
