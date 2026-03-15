# Termux Setup · justfile
#
# Full setup:         just
# Single step:        just packages / just dotfiles / just node / just claude / just vault
# Overrides:          GH_USER=someone OBSIDIAN_VAULT_REPO=my-vault just vault
#                     CHEZMOI_DOTFILES_REPO=my-dots just dotfiles
# Check status:       just status

set shell := ["bash", "-euo", "pipefail", "-c"]

gh_user       := env_var_or_default("GH_USER", "")
vault_repo    := env_var_or_default("OBSIDIAN_VAULT_REPO", "obsidian-vault")
chezmoi_repo  := env_var_or_default("CHEZMOI_DOTFILES_REPO", "dotfiles")
vault_name    := env_var_or_default("VAULT_NAME", vault_repo)
home          := env_var("HOME")
prefix        := env_var_or_default("PREFIX", "/data/data/com.termux/files/usr")
vault_shared  := home + "/storage/shared/Documents/" + vault_name
vault_git     := home + "/.git-repos/" + vault_name + ".git"

_check-termux:
    @[ -n "${TERMUX_VERSION:-}" ] || (echo "ERROR: Not running in Termux" && exit 1)

_cleanup-gh-token:
    #!/usr/bin/env bash
    if gh auth status &>/dev/null; then
        echo "==> Clearing gh token (setup complete, git will use SSH key)..."
        gh auth logout --hostname github.com 2>/dev/null || true
        echo "[OK] gh token cleared"
    fi

# Interactive menu (fzf TUI)
[group('setup')]
menu: _check-termux
    #!/usr/bin/env bash
    set -euo pipefail

    just --justfile "{{justfile()}}" status || true
    echo ""

    RECIPE=$(printf '%s\n' \
        "default  ·  Full setup — all steps with defaults" \
        "packages ·  Core packages (git, zsh, starship, etc.)" \
        "storage  ·  Grant shared storage access" \
        "github   ·  Authenticate with GitHub" \
        "xdg-ssh  ·  XDG dirs + SSH key (auto-registers with GitHub)" \
        "shell    ·  Set zsh as default shell" \
        "node     ·  Node LTS" \
        "claude   ·  Claude Code" \
        "vault    ·  Clone Obsidian vault" \
        "dotfiles ·  Apply chezmoi dotfiles" \
        "update   ·  Pull latest setup scripts + reopen menu" \
        "status   ·  Show installation status" \
        | fzf \
            --prompt="  Run › " \
            --header="Termux Setup  ·  Enter to run a step" \
            --height=100% \
            --border=rounded \
            --info=hidden \
    )

    [[ -z "$RECIPE" ]] && exit 0
    RECIPE="${RECIPE%% *}"

    just --justfile "{{justfile()}}" "$RECIPE"

# Pull latest scripts and reopen menu
[group('setup')]
update:
    git -C "{{justfile_directory()}}" pull --depth=1
    just --justfile "{{justfile()}}" menu

# Full setup (all steps in order)
[group('setup')]
default: _check-termux packages storage github xdg-ssh shell node claude vault dotfiles _cleanup-gh-token
    @echo ""
    @echo "Setup complete — run: exec zsh"
    @echo ""
    @just --justfile "{{justfile()}}" status

# Update Termux and install core packages
[group('setup')]
packages:
    pkg update -y && pkg upgrade -y
    pkg install -y $(grep -v '^\s*#' "{{justfile_directory()}}/pkg.txt" | grep -v '^\s*$' | tr '\n' ' ')
    @echo "[OK] Core packages installed"

# Grant shared storage access (Android permission popup)
[group('setup')]
storage:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d "{{home}}/storage" ]; then
        echo "==> Granting storage access — accept the popup on screen..."
        termux-setup-storage
        sleep 5
    fi
    echo "[OK] ~/storage/shared → /sdcard"

# Authenticate with GitHub (browser login)
[group('setup')]
github:
    #!/usr/bin/env bash
    set -euo pipefail
    if gh auth status &>/dev/null; then
        echo "[OK] GitHub authenticated as $(gh api user --jq .login)"
    else
        export BROWSER="termux-open-url"
        echo "==> A browser will open — paste the code shown below."
        gh auth login --web --git-protocol https --scopes admin:public_key
        git config --global credential.https://github.com.helper ''
        git config --global --add credential.https://github.com.helper '!gh auth git-credential'
        echo "[OK] GitHub authenticated as $(gh api user --jq .login)"
        echo "[INFO] Token stored in ~/.config/gh (no system keyring on Termux)."
        echo "       Token will be cleared after setup — git uses SSH keys going forward."
    fi

# Create XDG dirs, generate SSH key, register with GitHub
[group('setup')]
xdg-ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p \
        "{{home}}/.config" "{{home}}/.local/share" \
        "{{home}}/.cache"  "{{home}}/.local/state" \
        "{{home}}/.local/bin" "{{home}}/.ssh"
    chmod 700 "{{home}}/.ssh"

    KEY="{{home}}/.ssh/id_ed25519"
    if [ ! -f "$KEY" ]; then
        echo "==> Generating SSH key..."
        ssh-keygen -t ed25519 -C "termux-android" -f "$KEY" -N ""
    fi

    if gh auth status &>/dev/null; then
        FINGERPRINT=$(ssh-keygen -lf "$KEY" | awk '{print $2}')
        if ! gh ssh-key list | grep -q "$FINGERPRINT"; then
            echo "==> Adding SSH key to GitHub..."
            gh ssh-key add "${KEY}.pub" --title "termux-android"
            echo "[OK] SSH key registered with GitHub"
        else
            echo "[OK] SSH key already registered with GitHub"
        fi
    else
        echo "[WARN] Not authenticated with GitHub — SSH key not registered"
        echo "       Run: just github"
    fi
    echo "[OK] XDG dirs and SSH key ready"

# Apply chezmoi dotfiles
[group('setup')]
dotfiles repo=chezmoi_repo:
    #!/usr/bin/env bash
    set -euo pipefail
    GH_USER="{{gh_user}}"
    GH_USER="${GH_USER:-$(gh api user --jq .login 2>/dev/null || true)}"
    if [ -z "$GH_USER" ]; then
        echo "[WARN] Not authenticated — skipping dotfiles. Run: just github"
        exit 0
    fi
    REPO_FULL="${GH_USER}/{{repo}}"
    REPO_URL="git@github.com:${REPO_FULL}.git"

    if ! gh repo view "$REPO_FULL" &>/dev/null; then
        echo "Repository $REPO_FULL does not exist."
        read -rp "Create it as a private repo? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            gh repo create "$REPO_FULL" --private --add-readme
            echo "[OK] Created $REPO_FULL"
        else
            echo "[SKIP] Skipping dotfiles"
            exit 0
        fi
    fi

    echo "==> Applying chezmoi from $REPO_URL ..."
    if chezmoi init --apply "$REPO_URL"; then
        echo "[OK] chezmoi dotfiles applied"
        echo "     Update later: chezmoi update"
    else
        echo ""
        echo "[WARN] chezmoi apply failed — setup will continue without dotfiles."
        echo "       Fix your chezmoi repo and retry: chezmoi init --apply $REPO_URL"
        echo "       Or debug with: chezmoi diff"
    fi

# Set zsh as default shell
[group('setup')]
shell:
    chsh -s zsh 2>/dev/null || true
    @echo "[OK] Default shell set to zsh"

# Install Node LTS
[group('setup')]
node:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v node &>/dev/null; then
        echo "[OK] Node $(node --version) / npm $(npm --version) already installed"
    else
        echo "==> Installing Node LTS..."
        pkg install -y nodejs-lts
        echo "[OK] Node $(node --version) / npm $(npm --version)"
    fi

# Install Claude Code
[group('setup')]
claude:
    #!/usr/bin/env bash
    set -euo pipefail
    export TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

    echo "==> Installing @anthropic-ai/claude-code..."
    npm install -g @anthropic-ai/claude-code

    if claude --version &>/dev/null; then
        echo "[OK] Claude Code $(claude --version)"
    else
        echo "[WARN] Installed — open a new shell and run: claude --version"
    fi
    echo ""
    echo "Next: export ANTHROPIC_API_KEY=sk-ant-...  or just run: claude"

# Clone Obsidian vault
[group('setup')]
vault repo=vault_repo name=vault_name:
    #!/usr/bin/env bash
    set -euo pipefail
    GH_USER="{{gh_user}}"
    GH_USER="${GH_USER:-$(gh api user --jq .login 2>/dev/null || true)}"
    if [ -z "$GH_USER" ]; then
        echo "[WARN] Not authenticated — skipping vault. Run: just github"
        exit 0
    fi
    REPO_FULL="${GH_USER}/{{repo}}"
    REPO_URL="git@github.com:${REPO_FULL}.git"
    VAULT_SHARED="{{home}}/storage/shared/Documents/{{name}}"
    VAULT_GIT="{{home}}/.git-repos/{{name}}.git"

    git config --global pull.rebase true
    git config --global init.defaultBranch main
    git config --global core.checkStat minimal

    if ! gh repo view "$REPO_FULL" &>/dev/null; then
        echo "Repository $REPO_FULL does not exist."
        read -rp "Create it as a private repo? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            gh repo create "$REPO_FULL" --private --add-readme
            echo "[OK] Created $REPO_FULL"
        else
            echo "[SKIP] Skipping vault"
            exit 0
        fi
    fi

    if [ ! -d "$VAULT_GIT" ]; then
        echo "==> Cloning vault..."
        mkdir -p "$VAULT_SHARED" "$(dirname "$VAULT_GIT")"
        git clone --separate-git-dir="$VAULT_GIT" "$REPO_URL" "$VAULT_SHARED"
        git --git-dir="$VAULT_GIT" --work-tree="$VAULT_SHARED" \
            config core.worktree "$VAULT_SHARED"
        git config --global --add safe.directory "$VAULT_SHARED"
        echo "[OK] Vault cloned to $VAULT_SHARED"
    else
        echo "[OK] Vault already present — skipping clone"
    fi


# Show what's installed
[group('info')]
status:
    #!/usr/bin/env bash
    ok()   { printf "\033[32m[OK]\033[0m  %-12s %s\n" "$1" "$2"; }
    miss() { printf "\033[33m[--]\033[0m  %-12s not installed\n" "$1"; }
    if [ -z "${TERMUX_VERSION:-}" ]; then
        printf "\033[31m[!!]\033[0m  Not running in Termux — status not applicable\n"
        exit 0
    fi
    ok termux "v${TERMUX_VERSION}"
    gh auth status &>/dev/null && ok github "$(gh api user --jq .login 2>/dev/null)" || miss github
    command -v zsh      &>/dev/null && ok zsh      "$(zsh --version)"          || miss zsh
    command -v starship &>/dev/null && ok starship "$(starship --version)"     || miss starship
    command -v chezmoi  &>/dev/null && ok chezmoi  "$(chezmoi --version)"      || miss chezmoi
    command -v node     &>/dev/null && ok node     "$(node --version)"         || miss node
    command -v claude   &>/dev/null && ok claude   "$(claude --version 2>&1)"  || miss claude
    command -v gh       &>/dev/null && ok gh       "$(gh --version | head -1)" || miss gh
    [ -d "{{vault_git}}" ] \
        && ok vault "{{vault_shared}}" \
        || printf "\033[33m[--]\033[0m  %-12s not cloned (run: just vault)\n" vault
