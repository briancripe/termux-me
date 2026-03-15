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
pkg install -y git just

# Clone repo (public — no auth needed)
git clone --depth=1 "https://github.com/${OWNER}/${REPO}.git" "$DEST"

# Launch
cd "$DEST"
$AUTO && just default || just menu
