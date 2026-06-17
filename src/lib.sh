#!/usr/bin/env sh
# lib.sh - shared helpers for devhooks
# Sourced by pre-commit.sh and pre-push.sh — do not execute directly.

# ---------------------------------------------------------------------------
# Colours (disabled when not a TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_CYAN='\033[0;36m'
    C_DIM='\033[2m'
else
    C_RESET=''
    C_BOLD=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_CYAN=''
    C_DIM=''
fi

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
dh_info()    { printf "${C_CYAN}${C_BOLD}devhooks${C_RESET} %s\n" "$*"; }
dh_step()    { printf "${C_BOLD}  ==> %s${C_RESET}\n" "$*"; }
dh_ok()      { printf "${C_GREEN}  ✓ %s${C_RESET}\n" "$*"; }
dh_warn()    { printf "${C_YELLOW}  ! %s${C_RESET}\n" "$*" >&2; }
dh_error()   { printf "${C_RED}  ✗ %s${C_RESET}\n" "$*" >&2; }
dh_skip()    { printf "${C_DIM}  - %s (skipped)${C_RESET}\n" "$*"; }

# ---------------------------------------------------------------------------
# JSON helpers — uses php if available (no jq dependency needed)
# ---------------------------------------------------------------------------

# dh_json_get <file> <dot.separated.key>
# Returns the string value or empty string if not found.
dh_json_get() {
    _file="$1"
    _key="$2"
    if [ ! -f "$_file" ]; then
        echo ""
        return
    fi
    php -r "
        \$data = json_decode(file_get_contents('$_file'), true);
        \$keys = explode('.', '$_key');
        foreach (\$keys as \$k) {
            if (!is_array(\$data) || !array_key_exists(\$k, \$data)) { exit(0); }
            \$data = \$data[\$k];
        }
        if (is_string(\$data)) echo \$data;
    " 2>/dev/null || true
}

# dh_json_has_key <file> <dot.separated.key>
# Returns 0 (true) if key exists, 1 otherwise.
dh_json_has_key() {
    _file="$1"
    _key="$2"
    if [ ! -f "$_file" ]; then
        return 1
    fi
    _result="$(php -r "
        \$data = json_decode(file_get_contents('$_file'), true);
        \$keys = explode('.', '$_key');
        foreach (\$keys as \$k) {
            if (!is_array(\$data) || !array_key_exists(\$k, \$data)) { echo 'no'; exit; }
            \$data = \$data[\$k];
        }
        echo 'yes';
    " 2>/dev/null)" || true
    [ "$_result" = "yes" ]
}

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------

# dh_find_bin <name>
# Looks for <name> in vendor/bin/, node_modules/.bin/, then PATH.
dh_find_bin() {
    _name="$1"
    _project_root="$(git rev-parse --show-toplevel 2>/dev/null)"

    # vendor/bin (composer)
    if [ -x "$_project_root/vendor/bin/$_name" ]; then
        echo "$_project_root/vendor/bin/$_name"
        return
    fi
    # node_modules/.bin (npm/yarn/pnpm)
    if [ -x "$_project_root/node_modules/.bin/$_name" ]; then
        echo "$_project_root/node_modules/.bin/$_name"
        return
    fi
    # global PATH
    if command -v "$_name" >/dev/null 2>&1; then
        echo "$_name"
        return
    fi
    echo ""
}

# dh_has_composer_dep <package>
# Checks require-dev or require in composer.json for the given package name.
dh_has_composer_dep() {
    _pkg="$1"
    _root="$(git rev-parse --show-toplevel 2>/dev/null)"
    _file="$_root/composer.json"
    [ -f "$_file" ] || return 1
    php -r "
        \$data = json_decode(file_get_contents('$_file'), true);
        \$deps = array_merge(
            array_keys((array)(\$data['require'] ?? [])),
            array_keys((array)(\$data['require-dev'] ?? []))
        );
        foreach (\$deps as \$d) {
            if (strpos(\$d, '$_pkg') !== false) { echo 'yes'; exit; }
        }
        echo 'no';
    " 2>/dev/null | grep -q '^yes'
}

# dh_has_npm_dep <package>
# Checks devDependencies or dependencies in package.json.
dh_has_npm_dep() {
    _pkg="$1"
    _root="$(git rev-parse --show-toplevel 2>/dev/null)"
    _file="$_root/package.json"
    [ -f "$_file" ] || return 1
    php -r "
        \$data = json_decode(file_get_contents('$_file'), true);
        \$deps = array_merge(
            array_keys((array)(\$data['dependencies'] ?? [])),
            array_keys((array)(\$data['devDependencies'] ?? []))
        );
        foreach (\$deps as \$d) {
            if (\$d === '$_pkg') { echo 'yes'; exit; }
        }
        echo 'no';
    " 2>/dev/null | grep -q '^yes'
}

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

# dh_staged_php_files — list of staged .php files (added/modified)
dh_staged_php_files() {
    git diff --cached --name-only --diff-filter=ACM | grep '\.php$' || true
}

# dh_staged_js_ts_files — list of staged JS/TS files
dh_staged_js_ts_files() {
    git diff --cached --name-only --diff-filter=ACM | grep -E '\.(js|ts|jsx|tsx|mjs|cjs)$' || true
}

# dh_changed_files_since_push — files changed vs upstream (pre-push context)
dh_changed_files_since_push() {
    # REMOTE and SHA are passed via env from the pre-push hook stdin processing
    git diff --name-only --diff-filter=ACM "${DH_REMOTE_REF:-HEAD~1}..HEAD" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Test file resolution (Laravel/Pest convention)
# Converts app/Foo/Bar.php -> tests/Foo/BarTest.php
# Also checks tests/Unit/ and tests/Feature/ prefixes.
# ---------------------------------------------------------------------------
dh_find_test_for() {
    _src="$1"
    _root="$(git rev-parse --show-toplevel 2>/dev/null)"

    # Strip leading project root
    _rel="${_src#$_root/}"

    # Remove leading src/ or app/ segment
    _stripped="$(echo "$_rel" | sed 's|^app/||; s|^src/||')"

    # Build candidate paths
    _base="$(basename "$_stripped" .php)"
    _dir="$(dirname "$_stripped")"

    for _prefix in "tests" "tests/Unit" "tests/Feature"; do
        _candidate="$_root/$_prefix/$_dir/${_base}Test.php"
        if [ -f "$_candidate" ]; then
            echo "$_candidate"
            return
        fi
    done
}

# ---------------------------------------------------------------------------
# Run a tool, print result, return its exit code
# ---------------------------------------------------------------------------
dh_run() {
    _label="$1"
    shift
    dh_step "$_label"
    if "$@"; then
        dh_ok "$_label passed"
        return 0
    else
        dh_error "$_label failed"
        return 1
    fi
}
