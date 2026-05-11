# themeux

A lightweight bash theme switcher for Linux dotfiles. Define color palettes once in a `.theme` file, and themeux substitutes them into your config templates and symlinks everything into place — no extra dependencies beyond GNU coreutils and bash 4+.

WARNING: Made in large part by Claude Code, be careful when handling sensitive files.

## How it works

```
userHome/           # mirror of $HOME; files use {{VARIABLE}} placeholders
themes/             # one <name>.theme file per theme (KEY=value pairs)
active/             # auto-generated processed configs (git-ignored)
```

When you run `themeux apply <theme>`:

1. Each `{{VARIABLE}}` in `userHome/` templates is replaced with the matching value from the `.theme` file.
2. Processed files are written to `active/`.
3. Symlinks are created from `$HOME` (or `STOW_TARGET`) pointing into `active/`.

Switching themes cleans up the previous symlinks before laying down new ones.

## Use cases

- Swap between color schemes (Nord, Tokyo Night, …) across every app at once.
- Keep a single source of truth for colors. Change one value in a `.theme` file and it propagates everywhere.
- Works with any text-based config: Alacritty, Polybar, i3, tmux, zsh, Firefox userChrome, nvim, ...

## Installation

```sh
git clone <repo-url>
cd themeSwitcher
make install        # installs to ~/.local/bin/themeux
```

Requires `~/.local/bin` to be on your `PATH`. To uninstall:

```sh
make uninstall
```

## Usage

```
themeux apply <theme>     # apply a theme
themeux list              # list available themes
themeux status            # show the currently active theme
themeux scan              # list all {{VARIABLES}} used in userHome templates
themeux new-theme <name>  # scaffold a new .theme file from your templates
themeux unstow            # remove symlinks placed by the last apply
```

## Adding your own config files

Mirror the file's path under `userHome/` and replace any color or style values with `{{VARIABLE_NAME}}` placeholders:

```toml
# userHome/.config/alacritty/alacritty.toml
[colors.primary]
background = '{{ALACRITTY_BG}}'
foreground = '{{ALACRITTY_FG}}'
```

Run `themeux scan` to see every variable your templates reference, then make sure each `.theme` file defines them all.

## Creating a theme

Scaffold a new theme pre-populated with every variable your templates use:

```sh
themeux new-theme mytheme
```

Fill in the values in `themes/mytheme.theme`:

```sh
# Theme: mytheme
ALACRITTY_BG=#1e1e2e
ALACRITTY_FG=#cdd6f4
POLYBAR_BG=#1e1e2e
# ...
```

Then apply it:

```sh
themeux apply mytheme
```

## Configuration

The optional `config` file in the repo root lets you override the symlink target:

```sh
# config
STOW_TARGET=/home/yourname   # defaults to $HOME
```

Environment variables set before invoking `themeux` take precedence over `config`.
