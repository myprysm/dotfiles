#!/bin/bash
# Custom Claude Code statusline.
#   [CAVEMAN] <model> │ ctx <used>/<max> (<pct>) │ 5h <bar> <used>% ↻<reset> │ 7d <bar> <used>% ↻<reset>
#
# The caveman badge is delegated to the plugin's own script so it keeps working
# across plugin updates; everything after it is rendered here.

IN=$(cat)

# --- caveman badge (delegated) ----------------------------------------------
CAVEMAN=""
for candidate in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh; do
  [ -f "$candidate" ] && CAVEMAN="$candidate"
done
BADGE=""
[ -n "$CAVEMAN" ] && BADGE=$(printf '%s' "$IN" | bash "$CAVEMAN")

# --- fields -----------------------------------------------------------------
# One value per line, read with mapfile. A tab-separated `read` cannot carry an
# empty field: TAB is an IFS whitespace character, so a run of tabs collapses to
# one delimiter and every later field shifts left. With `resets_at` absent from
# one window — which the payload does omit — the next window's percentage landed
# in the timer and its own slot took the raw epoch, so the line printed a
# ten-digit number as a percentage beside a full bar.
mapfile -t FIELDS < <(
  printf '%s' "$IN" | jq -r 2>/dev/null '
    [ .model.display_name // "?"
    , (.context_window.used_percentage // 0)
    , (.context_window.total_input_tokens // 0)
    , (.context_window.context_window_size // 0)
    , (.rate_limits.five_hour.used_percentage // "")
    , (.rate_limits.five_hour.resets_at // "")
    , (.rate_limits.seven_day.used_percentage // "")
    , (.rate_limits.seven_day.resets_at // "")
    ] | .[]'
)
MODEL=${FIELDS[0]-}
CTX_PCT=${FIELDS[1]-}
CTX_IN=${FIELDS[2]-}
CTX_SIZE=${FIELDS[3]-}
H5_PCT=${FIELDS[4]-}
H5_RESET=${FIELDS[5]-}
D7_PCT=${FIELDS[6]-}
D7_RESET=${FIELDS[7]-}

# A malformed or unexpected payload must not spew shell errors into the prompt.
numeric_or() { # $1 = value, $2 = fallback
  local v=${1%%.*}
  case "$v" in
    ''|*[!0-9]*) printf '%s' "$2" ;;
    *)           printf '%s' "$v" ;;
  esac
}
MODEL=${MODEL:-?}
CTX_PCT=$(numeric_or "$CTX_PCT" 0)
CTX_IN=$(numeric_or "$CTX_IN" 0)
CTX_SIZE=$(numeric_or "$CTX_SIZE" 0)
H5_PCT=$(numeric_or "$H5_PCT" "")
H5_RESET=$(numeric_or "$H5_RESET" "")
D7_PCT=$(numeric_or "$D7_PCT" "")
D7_RESET=$(numeric_or "$D7_RESET" "")

DIM=$'\033[38;5;240m'
RESET=$'\033[0m'
SEP="${DIM} │ ${RESET}"

colour_for() { # $1 = percentage
  if   [ "$1" -ge 80 ]; then printf '\033[38;5;203m'
  elif [ "$1" -ge 50 ]; then printf '\033[38;5;220m'
  else                       printf '\033[38;5;114m'
  fi
}

bar() { # $1 = percentage, $2 = width
  local pct=$1 width=$2 filled i out
  [ "$pct" -gt 100 ] && pct=100
  filled=$(( pct * width / 100 ))
  out="$(colour_for "$pct")"
  for ((i = 0; i < filled; i++)); do out+="█"; done
  out+="$DIM"
  for ((i = filled; i < width; i++)); do out+="░"; done
  out+="$RESET"
  printf '%s' "$out"
}

human_tokens() { # $1 = token count
  local t=$1
  if   [ "$t" -ge 1000000 ]; then printf '%d.%dM' $(( t / 1000000 )) $(( t % 1000000 / 100000 ))
  elif [ "$t" -ge 1000 ];    then printf '%dk' $(( t / 1000 ))
  else                            printf '%d' "$t"
  fi
}

countdown() { # $1 = epoch seconds
  local left=$(( $1 - $(date +%s) ))
  [ "$left" -lt 0 ] && left=0
  if   [ "$left" -ge 86400 ]; then printf '%dd%dh' $(( left / 86400 )) $(( left % 86400 / 3600 ))
  elif [ "$left" -ge 3600 ];  then printf '%dh%02dm' $(( left / 3600 )) $(( left % 3600 / 60 ))
  else                             printf '%dm' $(( left / 60 ))
  fi
}

# --- badge + model ----------------------------------------------------------
# Without the caveman plugin the badge is empty, so the leading separator goes too.
LEAD=""
if [ -n "$BADGE" ]; then
  printf '%s' "$BADGE"
  LEAD="$SEP"
fi
MODEL_SHORT=${MODEL/ (1M context)/ 1M}
printf '%s\033[38;5;110m%s%s' "$LEAD" "$MODEL_SHORT" "$RESET"

# --- context ----------------------------------------------------------------
printf '%s%sctx%s %s%s%s%s/%s%s %s(%s%%)%s' \
  "$SEP" "$DIM" "$RESET" \
  "$(colour_for "$CTX_PCT")" "$(human_tokens "$CTX_IN")" "$RESET" \
  "$DIM" "$(human_tokens "$CTX_SIZE")" "$RESET" \
  "$(colour_for "$CTX_PCT")" "$CTX_PCT" "$RESET"

# --- rate-limit windows -----------------------------------------------------
window() { # $1 = label, $2 = percentage, $3 = reset epoch
  [ -z "$2" ] && return 0
  printf '%s%s%s%s %s %s%s%%%s' \
    "$SEP" "$DIM" "$1" "$RESET" \
    "$(bar "$2" 10)" \
    "$(colour_for "$2")" "$2" "$RESET"
  [ -n "$3" ] && printf '%s ↻%s%s' "$DIM" "$(countdown "$3")" "$RESET"
}

window "5h" "$H5_PCT" "$H5_RESET"
window "7d" "$D7_PCT" "$D7_RESET"
