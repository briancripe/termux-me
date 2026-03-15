#!/data/data/com.termux/files/usr/bin/bash
# This script is intentionally tiny so you can read it before trusting it.
#
# Run:
#   curl -fsSL https://termux.me | bash
#   curl -fsSL https://termux.me | bash -s -- --auto
#
# Or directly from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/briancripe/termux-me/main/termux-me.sh | bash

set -euo pipefail

OWNER="briancripe"
REPO="termux-me"
DEST="$HOME/termux-me"
AUTO=false
[[ "${1:-}" == "--auto" ]] && AUTO=true

# Install required packages for bootstrap
pkg update -y && pkg upgrade -y
pkg install -y git just fzf

# Clone or update repo (public — no auth needed)
EXPECTED_URL="https://github.com/${OWNER}/${REPO}.git"

if [ -d "$DEST/.git" ]; then
    ACTUAL_URL=$(git -C "$DEST" remote get-url origin 2>/dev/null || true)
    if [ "$ACTUAL_URL" != "$EXPECTED_URL" ]; then
        echo "ERROR: $DEST exists but points to $ACTUAL_URL (expected $EXPECTED_URL)"
        exit 1
    fi
    echo "==> Updating existing install..."
    git -C "$DEST" pull --depth=1
else
    git clone --depth=1 "$EXPECTED_URL" "$DEST"
fi

# Launch
cd "$DEST"
$AUTO && just default || just menu
