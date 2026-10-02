#!/usr/bin/env bash

# Bootstrap dotfiles via GNU stow.
#
# Usage:
#   ./install.sh              # stow all packages into $HOME
#   ./install.sh --bootstrap  # also run `brew bundle` first (new machines)
#
# Prereqs: Homebrew installed (https://brew.sh). Run with --bootstrap on a
# fresh machine to install fish/stow/etc. from brew/Brewfile before stowing.

set -euo pipefail

cd "$(dirname "$0")"

packages=(agents fish git gh ghostty herdr lazygit linearmouse nvim tidewave zed claude codex pi zsh ssh)

if [ "${1:-}" = --bootstrap ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew not found. Install it first: https://brew.sh"
        exit 1
    fi
    echo "Running brew bundle..."
    brew bundle --file=brew/Brewfile
fi

if ! command -v stow >/dev/null 2>&1; then
    echo "stow not found. Run: brew install stow"
    echo "(or re-run as: ./install.sh --bootstrap)"
    exit 1
fi

# herdr writes sockets and logs beside its config, so stow must not fold this dir into the repo.
mkdir -p "$HOME/.config/herdr"

for pkg in "${packages[@]}"; do
    if [ ! -d "$pkg" ]; then
        echo "skip   $pkg (not in repo)"
        continue
    fi
    echo "stow   $pkg"
    # fish/completions/*.fish are absolute symlinks into OrbStack.app, which stow
    # refuses to link; OrbStack recreates them itself, so leave them out.
    stow --target="$HOME" --ignore='(docker|kubectl|orbctl)\.fish' \
        --ignore='.*\.example' "$pkg"
done

# herdr owns its agent hook scripts, so install them rather than track them.
if command -v herdr >/dev/null 2>&1; then
    for agent in claude codex pi; do
        herdr integration install "$agent"
    done
else
    echo "skip   herdr integrations (herdr not installed)"
fi

# ~/.gitconfig includes ~/.gitconfig.local. Git ignores a missing include
# silently and falls back to user@hostname, so seed it rather than let commits
# go out with an identity GitHub cannot link to a profile.
if [ ! -f "$HOME/.gitconfig.local" ]; then
    cp git/.gitconfig.local.example "$HOME/.gitconfig.local"
    echo ""
    echo "Created ~/.gitconfig.local from the example. Fill in name, email and"
    echo "signingkey before committing, then check: git var GIT_AUTHOR_IDENT"
fi

echo ""
echo "Done. Symlinks point into $(pwd)."
