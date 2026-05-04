#!/usr/bin/env fish

# Bootstrap dotfiles via GNU stow.
#
# Usage:
#   ./install.fish              # stow all packages into $HOME
#   ./install.fish --bootstrap  # also run `brew bundle` first (new machines)
#
# Prereqs: Homebrew installed (https://brew.sh). Run with --bootstrap on a
# fresh machine to install fish/stow/etc. from brew/Brewfile before stowing.

cd (status dirname)

set -l packages fish git gh lazygit linearmouse tidewave zed claude zsh ssh

if test "$argv[1]" = --bootstrap
    if not type -q brew
        echo "Homebrew not found. Install it first: https://brew.sh"
        exit 1
    end
    echo "Running brew bundle..."
    brew bundle --file=brew/Brewfile
end

if not type -q stow
    echo "stow not found. Run: brew install stow"
    echo "(or re-run as: ./install.fish --bootstrap)"
    exit 1
end

for pkg in $packages
    if not test -d $pkg
        echo "skip   $pkg (not in repo)"
        continue
    end
    echo "stow   $pkg"
    stow --target=$HOME $pkg
end

echo ""
echo "Done. Symlinks point into "(pwd)"."
