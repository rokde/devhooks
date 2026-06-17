#!/usr/bin/env sh
# pre-push.sh — full suite + main-divergence check
# Sourced by bin/devhooks — do not execute directly.
#
# Runs all detected tools on the entire codebase.
# Also checks whether main has commits not yet in the current branch and
# asks for confirmation before allowing the push through.

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"

dh_info "pre-push — full suite"

FAILED=0

# ---------------------------------------------------------------------------
# 1. Main-divergence check
# ---------------------------------------------------------------------------
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
MAIN_BRANCH="main"

# Allow override via env: DEVHOOKS_MAIN_BRANCH=master devhooks pre-push
if [ -n "${DEVHOOKS_MAIN_BRANCH:-}" ]; then
    MAIN_BRANCH="$DEVHOOKS_MAIN_BRANCH"
fi

if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]; then
    dh_step "checking for diverged $MAIN_BRANCH"

    # Fetch quietly; ignore errors (no network, no remote, etc.)
    git fetch origin "$MAIN_BRANCH" --quiet 2>/dev/null || true

    # Count commits in origin/main that are NOT in the current branch
    AHEAD_COUNT="$(git rev-list --count "HEAD..origin/$MAIN_BRANCH" 2>/dev/null || echo 0)"

    if [ "$AHEAD_COUNT" -gt 0 ]; then
        dh_warn "origin/$MAIN_BRANCH has $AHEAD_COUNT commit(s) not yet in '$CURRENT_BRANCH'"
        dh_warn "Consider: git fetch origin && git rebase origin/$MAIN_BRANCH"
        printf "${C_YELLOW}  Push anyway? [y/N] ${C_RESET}"
        read -r ANSWER </dev/tty
        case "$ANSWER" in
            y|Y|yes|YES) dh_warn "continuing push despite diverged $MAIN_BRANCH" ;;
            *)
                dh_error "push aborted — integrate $MAIN_BRANCH changes first"
                exit 1
                ;;
        esac
    else
        dh_ok "$MAIN_BRANCH is up-to-date"
    fi
else
    dh_skip "main-divergence check (on $MAIN_BRANCH branch)"
fi

# ---------------------------------------------------------------------------
# 2. PHP tools — full codebase
# ---------------------------------------------------------------------------

# Rector
RECTOR="$(dh_find_bin rector)"
if [ -n "$RECTOR" ]; then
    dh_run "rector" "$RECTOR" process --dry-run || FAILED=1
else
    dh_skip "rector (not installed)"
fi

# Pint
PINT="$(dh_find_bin pint)"
if [ -n "$PINT" ]; then
    dh_run "pint" "$PINT" || FAILED=1
else
    dh_skip "pint (not installed)"
fi

# PHPStan
PHPSTAN="$(dh_find_bin phpstan)"
if [ -n "$PHPSTAN" ]; then
    dh_run "phpstan" "$PHPSTAN" analyse || FAILED=1
else
    dh_skip "phpstan (not installed)"
fi

# Pest — full suite
PEST="$(dh_find_bin pest)"
if [ -n "$PEST" ]; then
    dh_run "pest" "$PEST" || FAILED=1
else
    dh_skip "pest (not installed)"
fi

# ---------------------------------------------------------------------------
# 3. JS/TS tools — full codebase
# ---------------------------------------------------------------------------

# oxlint
OXLINT="$(dh_find_bin oxlint)"
if [ -n "$OXLINT" ]; then
    dh_run "oxlint" "$OXLINT" . || FAILED=1
else
    dh_skip "oxlint (not installed)"
fi

# oxfmt
OXFMT="$(dh_find_bin oxfmt)"
if [ -n "$OXFMT" ]; then
    dh_run "oxfmt" "$OXFMT" --check . || FAILED=1
else
    dh_skip "oxfmt (not installed)"
fi

# Vitest — full suite
VITEST="$(dh_find_bin vitest)"
if [ -n "$VITEST" ]; then
    dh_run "vitest" "$VITEST" run || FAILED=1
else
    dh_skip "vitest (not installed)"
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    dh_error "pre-push checks failed — push aborted"
    exit 1
fi

dh_ok "all pre-push checks passed"
exit 0
