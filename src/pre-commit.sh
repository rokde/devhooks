#!/usr/bin/env sh
# pre-commit.sh — fast checks on staged files only
# Sourced by bin/devhooks — do not execute directly.
#
# PHP tools run only on staged PHP files (or their discovered test counterparts).
# JS/TS tools run only on staged JS/TS files.
# Tools are skipped when not present in vendor/bin, node_modules/.bin or PATH.

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"

dh_info "pre-commit — checking staged files"

FAILED=0

# ---------------------------------------------------------------------------
# Collect staged files
# ---------------------------------------------------------------------------
STAGED_PHP="$(dh_staged_php_files)"
STAGED_JS="$(dh_staged_js_ts_files)"

if [ -z "$STAGED_PHP" ] && [ -z "$STAGED_JS" ]; then
    dh_ok "nothing to check (no staged PHP/JS/TS files)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Resolve test files for staged PHP sources
# ---------------------------------------------------------------------------
TEST_FILES=""
if [ -n "$STAGED_PHP" ]; then
    for f in $STAGED_PHP; do
        full="$PROJECT_ROOT/$f"
        # If the staged file is itself a test file, use it directly
        case "$f" in
            tests/*|test/*)
                if [ -f "$full" ]; then
                    TEST_FILES="$TEST_FILES $full"
                fi
                ;;
            *)
                test_file="$(dh_find_test_for "$full")"
                if [ -n "$test_file" ]; then
                    TEST_FILES="$TEST_FILES $test_file"
                fi
                ;;
        esac
    done
fi

# ---------------------------------------------------------------------------
# PHP: Rector (on staged files only)
# ---------------------------------------------------------------------------
if [ -n "$STAGED_PHP" ]; then
    RECTOR="$(dh_find_bin rector)"
    if [ -n "$RECTOR" ]; then
        # shellcheck disable=SC2086
        dh_run "rector (staged)" "$RECTOR" process --dry-run $STAGED_PHP || FAILED=1
    fi
fi

# ---------------------------------------------------------------------------
# PHP: Pint (on staged files only)
# ---------------------------------------------------------------------------
if [ -n "$STAGED_PHP" ]; then
    PINT="$(dh_find_bin pint)"
    if [ -n "$PINT" ]; then
        # shellcheck disable=SC2086
        dh_run "pint (staged)" "$PINT" $STAGED_PHP || FAILED=1
    fi
fi

# ---------------------------------------------------------------------------
# PHP: PHPStan (on staged files only)
# ---------------------------------------------------------------------------
if [ -n "$STAGED_PHP" ]; then
    PHPSTAN="$(dh_find_bin phpstan)"
    if [ -n "$PHPSTAN" ]; then
        # shellcheck disable=SC2086
        dh_run "phpstan (staged)" "$PHPSTAN" analyse --memory-limit=-1 $STAGED_PHP || FAILED=1
    fi
fi

# ---------------------------------------------------------------------------
# PHP: Pest (only the test files that correspond to staged sources)
# ---------------------------------------------------------------------------
if [ -n "$STAGED_PHP" ]; then
    PEST="$(dh_find_bin pest)"
    if [ -n "$PEST" ]; then
        if [ -n "$TEST_FILES" ]; then
            # Build --filter or file args depending on what pest supports
            # Pest accepts file paths directly
            # shellcheck disable=SC2086
            dh_run_pest "pest (related tests)" "$PEST" $TEST_FILES || FAILED=1
        else
            dh_skip "pest (no related test files found for staged sources)"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# JS/TS: oxlint (on staged files only)
# ---------------------------------------------------------------------------
if [ -n "$STAGED_JS" ]; then
    OXLINT="$(dh_find_bin oxlint)"
    if [ -n "$OXLINT" ]; then
        # shellcheck disable=SC2086
        dh_run "oxlint (staged)" "$OXLINT" $STAGED_JS || FAILED=1
    fi
fi

# ---------------------------------------------------------------------------
# JS/TS: dprint / oxfmt (on staged files only)
# ---------------------------------------------------------------------------
if [ -n "$STAGED_JS" ]; then
    OXFMT="$(dh_find_bin oxfmt)"
    if [ -n "$OXFMT" ]; then
        # shellcheck disable=SC2086
        dh_run "oxfmt (staged)" "$OXFMT" --check $STAGED_JS || FAILED=1
    fi
fi

# ---------------------------------------------------------------------------
# JS/TS: Vitest (run related tests via --changed or explicit file matching)
# ---------------------------------------------------------------------------
if [ -n "$STAGED_JS" ]; then
    VITEST="$(dh_find_bin vitest)"
    if [ -n "$VITEST" ]; then
        # vitest accepts file globs / paths; we pass the staged files and let
        # vitest figure out which tests are related via its --changed logic.
        # Using 'run' to avoid watch mode.
        # shellcheck disable=SC2086
        dh_run "vitest (related)" "$VITEST" run --reporter=verbose $STAGED_JS || FAILED=1
    fi
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    dh_error "pre-commit checks failed"
    printf "${C_YELLOW}  Commit anyway? [y/N] ${C_RESET}"
    read -r ANSWER </dev/tty
    case "$ANSWER" in
        y|Y|yes|YES) dh_warn "committing despite failed checks" ;;
        *)
            dh_error "commit aborted"
            exit 1
            ;;
    esac
fi

dh_ok "all pre-commit checks passed"
exit 0
