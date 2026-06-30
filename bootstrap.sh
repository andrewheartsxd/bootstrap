#!/bin/bash
set -euo pipefail

# Detect operating system
OS="$(uname -s)"

echo "🚀 Starting bootstrap for OS: $OS"

# 1. Install Git based on OS
if [ "$OS" = "Darwin" ]; then
    # macOS
    if ! command -v git &> /dev/null; then
        echo "📦 Git not found. Installing Xcode Command Line Tools..."
        # This triggers the macOS native git/developer tools installer
        xcode-select --install || true
        echo "🔔 Please complete the Xcode CLI installation pop-up, then re-run this script."
        exit 1
    fi
elif [ "$OS" = "Linux" ]; then
    # Linux (Ubuntu/WSL2)
    if ! command -v git &> /dev/null; then
        echo "📦 Git not found. Installing via apt..."
        sudo apt-get update
        sudo apt-get install -y git
    fi
else
    echo "❌ Unsupported OS: $OS"
    exit 1
fi

echo "✅ Git is ready."

# 2. Install chezmoi via the official curl one-liner
if ! command -v chezmoi &> /dev/null; then
    echo "🐿️ Installing chezmoi..."
    # Installs chezmoi to ~/.local/bin, then adds it to PATH)
    sh -c "$(curl -fsLS get.chezmoi.io/lb)"
    export PATH="$HOME/.local/bin:$PATH"
fi

echo "✅ chezmoi is ready."

# 3. Use chezmoi to apply dotfiles
if [ -d "$HOME/.local/share/chezmoi" ]; then
    # chezmoi is already initialized, so just apply the dotfiles
    echo "🔄 Running chezmoi apply..."
    chezmoi apply
else
    # Prompt the user for their GitHub username
    read -r -p "👤 Enter the GitHub username for your dotfiles repo: " GH_USER
    # Quick sanity check: If the user just hits enter, throw an error and exit
    if [ -z "$GH_USER" ]; then
        echo "❌ Error: GitHub username cannot be empty."
        exit 1
    fi

    # Create SSH key for private dotfiles repo and add it to GitHub
    read -r -p "🔑 Enter SSH key name for this machine (e.g., work-mac): " SSH_KEY_LABEL

    if [ -z "$SSH_KEY_LABEL" ]; then
        echo "❌ Error: SSH key name cannot be empty."
        exit 1
    fi

    SSH_KEY_NAME="${SSH_KEY_LABEL}_${GH_USER}"
    SSH_KEY_PATH="$HOME/.ssh/$SSH_KEY_NAME"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if [ ! -f "$SSH_KEY_PATH" ]; then
        ssh-keygen -t ed25519 -a 100 -C "$SSH_KEY_LABEL" -f "$SSH_KEY_PATH"
    fi

    # optionally add the SSH key to the ssh-agent if available
    if command -v ssh-add >/dev/null 2>&1 && command -v ssh-agent >/dev/null 2>&1; then
        eval "$(ssh-agent -s)"
        ssh-add "$SSH_KEY_PATH"
    else
        echo "⚠️ ssh-agent or ssh-add not found; skipping ssh-add."
    fi

    echo "Add this SSH public key to GitHub:"
    echo
    cat "$SSH_KEY_PATH.pub"
    echo
    echo "Open: https://github.com/settings/keys"
    read -r -p "Press Enter after you've added the key to GitHub..."

    echo "🧪 Testing SSH access to GitHub..."
    echo "🔍 Expected success message: Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.)"
    # test access before continuing
    SSH_TEST_OUTPUT="$(ssh -T -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes git@github.com 2>&1 || true)"
    echo "$SSH_TEST_OUTPUT"
    if echo "$SSH_TEST_OUTPUT" | grep -q "successfully authenticated"; then
        echo "❌ SSH authentication failed. Make sure the public key was added to GitHub, then re-run this script."
        exit 1
    fi

    echo "🆕 Initializing chezmoi from GitHub..."
    # Initialize chezmoi from GitHub using the previously generated SSH key
    GIT_SSH_COMMAND="ssh -i \"$SSH_KEY_PATH\" -o IdentitiesOnly=yes" \
        chezmoi init --apply \
        --data "ssh_key_name=$SSH_KEY_NAME" \
        "git@github.com:$GH_USER/dotfiles.git"
fi

echo "🎉 Bootstrapping complete!"
