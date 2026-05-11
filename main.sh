#!/bin/bash
# Theme Switcher — apply color/style themes to config files via symlinks
#
# Usage:  themeux <command> [args]
#
# Directory layout:
#   userHome/   — mirror of $HOME; files use {{VARIABLE}} placeholder syntax
#   themes/     — one <name>.theme file per theme (KEY=value pairs)
#   active/     — auto-generated; do not edit by hand
#   config      — optional settings (e.g. STOW_TARGET)

set -euo pipefail

SCRIPT_DIR="__THEMEUX_DIR__"
THEMES_DIR="$SCRIPT_DIR/themes"
USER_HOME_DIR="$SCRIPT_DIR/userHome"
ACTIVE_DIR="$SCRIPT_DIR/active"
CONFIG_FILE="$SCRIPT_DIR/config"
ACTIVE_THEME_FILE="$SCRIPT_DIR/.active_theme"
IGNORE_FILE="$SCRIPT_DIR/themeux.ignore"

# Load user config first; environment variables set before invoking the script take precedence
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Fall back to $HOME if config (or env) did not set STOW_TARGET
STOW_TARGET="${STOW_TARGET:-$HOME}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "Error: $*" >&2; exit 1; }

# Return 0 if the relative path should be excluded per themeux.ignore.
# Patterns without a slash are matched against the basename only.
# Patterns with a slash are matched against the full relative path.
is_ignored() {
    local rel_path="$1"
    [[ -f "$IGNORE_FILE" ]] || return 1

    local filename
    filename="$(basename "$rel_path")"

    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        if [[ "$pattern" == */* ]]; then
            [[ "$rel_path" == $pattern ]] && return 0
        else
            [[ "$filename" == $pattern ]] && return 0
        fi
    done < "$IGNORE_FILE"
    return 1
}

# For each file in active/, create a symlink at the corresponding path under
# $STOW_TARGET. mkdir -p follows existing directory symlinks (e.g. ~/.config ->
# dotfiles/.config), so intermediate paths are handled correctly.
link_active() {
    while IFS= read -r -d '' src_file; do
        local relative="${src_file#"$ACTIVE_DIR"/}"
        local dest="$STOW_TARGET/$relative"
        mkdir -p "$(dirname "$dest")"
        ln -sf "$src_file" "$dest"
    done < <(find "$ACTIVE_DIR" -type f -print0)
}

# Remove every symlink under $STOW_TARGET that points into $ACTIVE_DIR.
unlink_active() {
    while IFS= read -r -d '' src_file; do
        local relative="${src_file#"$ACTIVE_DIR"/}"
        local dest="$STOW_TARGET/$relative"
        if [[ -L "$dest" ]]; then
            local target
            target="$(readlink "$dest")"
            # Resolve relative symlinks so we can compare against $ACTIVE_DIR
            [[ "$target" != /* ]] && target="$(dirname "$dest")/$target"
            target="$(realpath -m "$target")"
            if [[ "$target" == "$ACTIVE_DIR"/* ]]; then
                rm "$dest"
            fi
        fi
    done < <(find "$ACTIVE_DIR" -type f -print0)
}

# Load KEY=value pairs from a .theme file into a named associative array.
# Lines starting with # and blank lines are ignored.
# Values may contain = (only the first = on a line is the delimiter).
load_theme() {
    local theme_file="$1"
    local -n _vars="$2"

    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local key="${line%%=*}"
        local value="${line#*=}"
        _vars["$key"]="$value"
    done < "$theme_file"
}

# Substitute every {{VARIABLE}} in src with the matching theme value, write to dest.
# Uses bash parameter expansion so special characters in values are treated literally.
process_file() {
    echo "Processing $1"
    local src="$1"
    local dest="$2"
    local -n _theme="$3"

    # Append a sentinel so command substitution does not strip trailing newlines
    local content
    content=$(cat "$src"; printf x)
    content="${content%x}"

    for key in "${!_theme[@]}"; do
        content="${content//\{\{$key\}\}/${_theme[$key]}}"
    done

    printf '%s' "$content" > "$dest"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_apply() {
    local theme_name="${1:-}"
    [[ -n "$theme_name" ]] || die "No theme specified. Run '$(basename "$0") list' to see options."

    local theme_file="$THEMES_DIR/$theme_name.theme"
    [[ -f "$theme_file" ]] || die "Theme '$theme_name' not found (expected $theme_file)."

    declare -A theme_vars
    load_theme "$theme_file" theme_vars

    # Remove previous symlinks before regenerating active/ to avoid dangling links
    if [[ -d "$ACTIVE_DIR" ]]; then
        unlink_active
        rm -rf "$ACTIVE_DIR"
    fi
    mkdir -p "$ACTIVE_DIR"

    # Process every template file from userHome into active/
    local file_count=0
    local ignored_count=0
    while IFS= read -r -d '' src_file; do
        local relative_path="${src_file#"$USER_HOME_DIR"/}"

        if is_ignored "$relative_path"; then
            ignored_count=$(( ignored_count + 1 ))
            continue
        fi

        local dest_file="$ACTIVE_DIR/$relative_path"

        mkdir -p "$(dirname "$dest_file")"
        if grep -qI '' "$src_file" 2>/dev/null; then
            process_file "$src_file" "$dest_file" theme_vars
        else
            cp "$src_file" "$dest_file"
        fi

        file_count=$(( file_count + 1 ))
    done < <(find "$USER_HOME_DIR" -type f -print0)

    echo "Processed $file_count file(s) into active/ (ignored: $ignored_count)"

    # Create symlinks from STOW_TARGET pointing into active/
    link_active

    printf '%s\n' "$theme_name" > "$ACTIVE_THEME_FILE"
    echo "Applied theme: $theme_name  (symlinks placed in $STOW_TARGET)"
}

cmd_list() {
    echo "Available themes:"
    local found=0
    for theme_file in "$THEMES_DIR"/*.theme; do
        [[ -f "$theme_file" ]] || continue
        echo "  $(basename "$theme_file" .theme)"
        found=1
    done
    [[ $found -eq 1 ]] || echo "  (none — add .theme files to $THEMES_DIR)"
}

cmd_status() {
    if [[ -f "$ACTIVE_THEME_FILE" ]] && [[ -s "$ACTIVE_THEME_FILE" ]]; then
        echo "Active theme: $(cat "$ACTIVE_THEME_FILE")"
    else
        echo "No theme currently applied."
    fi
}

# Print every {{VARIABLE}} found across all userHome templates
cmd_scan() {
    echo "Variables referenced in userHome templates:"
    local vars
    vars=$(grep -rhoE '\{\{[A-Z0-9_]+\}\}' "$USER_HOME_DIR" 2>/dev/null | sort -u)
    if [[ -n "$vars" ]]; then
        echo "$vars" | sed 's/^/  /'
    else
        echo "  (none found — userHome may be empty)"
    fi
}

# Scaffold a new .theme file pre-populated with every variable found in userHome
cmd_new_theme() {
    local theme_name="${1:-}"
    [[ -n "$theme_name" ]] || die "No theme name specified."

    local theme_file="$THEMES_DIR/$theme_name.theme"
    [[ ! -f "$theme_file" ]] || die "Theme '$theme_name' already exists at $theme_file."

    {
        printf '# Theme: %s\n\n' "$theme_name"

        grep -rhoE '\{\{[A-Z0-9_]+\}\}' "$USER_HOME_DIR" 2>/dev/null \
            | sort -u \
            | sed 's/{{//; s/}}//' \
            | while IFS= read -r var; do
                printf '%s=\n' "$var"
              done
    } > "$theme_file"

    echo "Created $theme_file"
    echo "Fill in the values, then run: $(basename "$0") apply $theme_name"
}

cmd_unstow() {
    if [[ ! -d "$ACTIVE_DIR" ]]; then
        echo "No active/ directory found; nothing to remove."
        return
    fi
    unlink_active
    printf '' > "$ACTIVE_THEME_FILE"
    echo "Removed symlinks from $STOW_TARGET."
}

cmd_help() {
    cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  apply <theme>     Substitute theme values into userHome templates, then symlink
  list              List available themes
  status            Show the currently active theme
  scan              List all {{VARIABLES}} used across userHome templates
  new-theme <name>  Create a scaffolded .theme file from userHome variables
  unstow            Remove symlinks placed by the last apply

Template syntax (in userHome files):
  Use {{VARIABLE_NAME}} where a theme value should be inserted.
  Variable names must match [A-Z0-9_]+.

Theme file format (themes/<name>.theme):
  # Lines starting with # are comments
  BG_COLOR=#1e1e2e
  FONT_FAMILY=JetBrains Mono
  FONT_SIZE=14

Configuration (./config):
  STOW_TARGET   Directory where symlinks are placed (default: \$HOME)

Ignore file (./themeux.ignore):
  List patterns (one per line) for files in userHome/ to skip.
  Patterns without a slash match the filename at any depth.
  Patterns with a slash match the full path relative to userHome/.
  Lines starting with # are comments.
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

case "${1:-}" in
    apply)          cmd_apply     "${2:-}" ;;
    list)           cmd_list               ;;
    status)         cmd_status             ;;
    scan)           cmd_scan               ;;
    new-theme)      cmd_new_theme "${2:-}" ;;
    unstow)         cmd_unstow             ;;
    help|--help|-h) cmd_help               ;;
    *)              cmd_help; exit 1       ;;
esac
