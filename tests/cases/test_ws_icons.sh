#!/usr/bin/env bash
set -Eeuo pipefail

# The workspace strip: the catalogue is well formed, the renderer resolves
# icons with initialClass over class over title over default, unmapped and
# special windows never show, a class that changes after launch changes the
# glyph, and the listener turns a recorded socket2 trace into one cache and
# fewer Waybar signals than events, ignoring events that change nothing.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
waybar="$repo_root/dotfiles/waybar/.config/waybar"
fixture="$repo_root/tests/data/ws"
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/vivac-wsicons.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}

# --- catalogue ------------------------------------------------------------------------------------------------
jq -e '
	(.default | type == "string" and length > 0)
	and all([.classes, .prefixes, .titles][] | to_entries[]; (.key | length > 0) and (.value | type == "string" and length > 0))
	and ((.classes | length) >= 30)' "$waybar/workspace-icons.json" >/dev/null || fail 'catalogue: default missing, an empty key or glyph, or fewer than 30 classes'

# --- replay: the trace produces a cache and signals fewer times than there are events ---------------------
printf '#!/usr/bin/env bash\nprintf x >>"%s"\n' "$sandbox/signals" >"$sandbox/notify"
chmod +x "$sandbox/notify"
WS_FIXTURE="$fixture" PATH="$fixture/bin:$PATH" WS_CACHE="$sandbox/cache.json" WS_DEBOUNCE=0.2 \
	WS_NOTIFY="$sandbox/notify" bash "$waybar/scripts/ws-refresh.sh" --replay "$fixture/socket2.trace" || fail 'replay failed'
[[ -s "$sandbox/cache.json" ]] || fail 'replay wrote no cache'
signals="$(wc -c <"$sandbox/signals")"
relevant="$(grep -Ec '^(workspace|focusedmon|openwindow|closewindow|movewindow|windowtitle|urgent|activewindow)' "$fixture/socket2.trace")"
((signals >= 1 && signals < relevant)) || fail "expected fewer signals than relevant events (got $signals for $relevant)"
jq -e '.active == 2 and ([.workspaces[].id] | index(-99) == null)' "$sandbox/cache.json" >/dev/null || fail 'cache: wrong active workspace or a special workspace leaked in'
jq -e '[.workspaces[] | select(.id == 1)][0].urgent == true' "$sandbox/cache.json" >/dev/null || fail 'cache: the urgent window on workspace 1 was lost'
jq -e '[.workspaces[] | select(.id == 4)][0].windows | length == 1' "$sandbox/cache.json" >/dev/null || fail 'cache: an unmapped window is listed'

# --- render: golden string ----------------------------------------------------------------------------------
render() {
	WS_CACHE="$1" WS_ICONS="$waybar/workspace-icons.json" bash "$waybar/scripts/ws-render.sh"
}
out="$(render "$sandbox/cache.json")"
[[ "$out" == "$(<"$repo_root/tests/data/ws/golden/render.json")" ]] || {
	printf 'expected: %s\ngot:      %s\n' "$(<"$repo_root/tests/data/ws/golden/render.json")" "$out" >&2
	fail 'render differs from the golden (tests/update-golden.sh if intended)'
}
text="$(jq -r .text <<<"$out")"
# shellcheck disable=SC2001  # strip pango tags; parameter expansion cannot do a non-greedy tag match
plain="$(sed 's/<[^>]*>//g' <<<"$text")"
for n in 1 2 3 4 5 6 7 8 9 10; do
	grep -Eq "(^|  )$n( |$)" <<<"$plain" || fail "button $n is missing its number: $plain"
done
[[ "$text" == *'underline="single">2 '* ]] || fail 'active workspace 2 is not the underlined one'
[[ "$text" == *'style="italic">1 '* ]] || fail 'urgent workspace 1 is not the italic one'
grep -q '&lt;shell&gt;' <<<"$(jq -r .tooltip <<<"$out")" || fail 'a title with markup reached the tooltip unescaped'
[[ "$text" != *shell* && "$text" != *Firefox* ]] || fail 'window text leaked into the strip markup'

# --- precedence: initialClass beats class beats title beats default --------------------------------------
glyph() { jq -r --arg k "$1" '.classes[$k]' "$waybar/workspace-icons.json"; }
[[ "$plain" == *"4 $(glyph kitty)"* ]] || fail 'initialClass kitty did not beat class Spotify'
[[ "$plain" == *"3 $(jq -r .default "$waybar/workspace-icons.json") $(glyph firefox)"* ]] || fail 'class-less windows: default then title fallback expected'
[[ "$plain" == *"5 $(jq -r '.prefixes["jetbrains-"]' "$waybar/workspace-icons.json")"* ]] || fail 'prefix rule for jetbrains- not applied'

# --- a class that changes after launch changes the glyph ------------------------------------------------------
later="$sandbox/later"
mkdir -p -- "$later"
cp -- "$fixture"/*.json "$later/"
jq '[.[] | if .address == "0x4a" then .initialClass = "" else . end]' "$fixture/clients.json" >"$later/clients.json"
WS_FIXTURE="$later" PATH="$fixture/bin:$PATH" WS_CACHE="$later/cache.json" WS_NOTIFY=true bash "$waybar/scripts/ws-refresh.sh" --once
# shellcheck disable=SC2001
[[ "$(render "$later/cache.json" | jq -r .text | sed 's/<[^>]*>//g')" == *"4 $(glyph Spotify)"* ]] || fail 'post-launch class change not reflected'

printf 'workspace icons: catalogue valid, replay debounced, golden render, precedence, post-launch change\n'
