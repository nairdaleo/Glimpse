#!/bin/bash
# Prepares this Mac for working on Glimpse. It prints every command before
# running it, asks before installing anything, never uses sudo, and is safe to
# run again. Pass --yes to skip the install prompt.
set -euo pipefail
cd "$(dirname "$0")"

yes=0; [[ "${1:-}" == "--yes" ]] && yes=1
step() { printf '\n==> %s\n' "$1"; }
run()  { printf '    $ %s\n' "$*"; "$@"; }
ok()   { printf '    ok: %s\n' "$1"; }
changed=()

step "1/4 Check the toolchain (read-only)"
[[ "$(uname)" == "Darwin" ]] || { echo "    Glimpse builds on macOS only." >&2; exit 1; }
ok "macOS $(sw_vers -productVersion)"
if ! xcode-select -p >/dev/null 2>&1; then
    echo "    Xcode is not selected. Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app" >&2; exit 1
fi
ok "developer tools at $(xcode-select -p)"
ok "$(swift --version 2>/dev/null | head -1)"

step "2/4 Install betterleaks (secret scanner used by the push hook)"
if command -v betterleaks >/dev/null 2>&1; then
    ok "betterleaks $(betterleaks version) already installed"
elif ! command -v brew >/dev/null 2>&1; then
    echo "    Homebrew is missing. Install betterleaks yourself (https://betterleaks.com), then rerun." >&2; exit 1
else
    echo "    This will run: brew install betterleaks"
    if (( ! yes )); then read -r -p "    Install it now? [y/N] " answer; [[ "$answer" =~ ^[Yy] ]] || { echo "    Skipped. Pushes stay blocked until it is installed."; }; fi
    if (( yes )) || [[ "${answer:-}" =~ ^[Yy] ]]; then run brew install betterleaks; changed+=("installed betterleaks (undo: brew uninstall betterleaks)"); fi
fi

step "3/4 Enable the repository's git hooks (.githooks/)"
echo "    pre-push scans the commits you push for secrets and blocks the push if it finds one."
if [[ "$(git config --get core.hooksPath || true)" == ".githooks" ]]; then
    ok "core.hooksPath is already .githooks"
else
    run git config core.hooksPath .githooks
    changed+=("set git config core.hooksPath=.githooks in this clone (undo: git config --unset core.hooksPath)")
fi

step "4/4 Fetch Swift package dependencies (pinned Sparkle)"
run swift package resolve
ok "packages resolved into .build/ (delete .build/ to undo)"

printf '\n==> Done.\n'
if (( ${#changed[@]} )); then printf '    Changed on this Mac:\n'; printf '    - %s\n' "${changed[@]}"; else echo "    Nothing needed changing."; fi
cat <<'NEXT'
    Next:
      swift test
      ./scripts/build-app.sh && open build/Glimpse.app
NEXT
