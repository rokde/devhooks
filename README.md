# devhooks

Lightweight git hooks runner for PHP/JS projects.

- **pre-commit** — runs only on staged files (fast)
- **pre-push** — runs full suite + checks for diverged `main` branch

Detects installed tools automatically from `vendor/bin/` and `node_modules/.bin/`. No configuration required.

## Installation

### Per-project (recommended)

```bash
composer require --dev rokde/devhooks
vendor/bin/devhooks init
```

### Global

Install once and use across all projects without adding it to each `composer.json`:

```bash
composer global require rokde/devhooks
devhooks init
```

When installed globally, `devhooks init` writes hooks that call `devhooks` via
`$PATH`. When installed locally, hooks call `vendor/bin/devhooks` instead.
Both modes are detected automatically — no extra configuration needed.

`init` writes `.git/hooks/pre-commit` and `.git/hooks/pre-push` and can be
re-run at any time to update the hooks to the latest version.

> **Note:** `.git/hooks/` is never committed to the repository. Each developer
> needs to run `devhooks init` once after cloning, regardless of whether they
> use a local or global installation.

## Commands

| Command | Description |
|---|---|
| `devhooks init` | Install/update git hooks in `.git/hooks/` |
| `devhooks remove` | Remove devhooks-managed hooks from `.git/hooks/` |
| `devhooks pre-commit` | Run fast checks on staged files only |
| `devhooks pre-push` | Run full suite + main-divergence check |

You can also invoke the commands directly without going through the git hook:

```bash
# local install
vendor/bin/devhooks pre-commit

# global install
devhooks pre-commit
```

## What runs when

### pre-commit (staged files only)

Only files staged for the current commit are checked. For PHP source files,
the corresponding test file is resolved automatically and passed to Pest.

| Tool | Scope |
|---|---|
| `rector` | staged `.php` files |
| `pint` | staged `.php` files |
| `phpstan` | staged `.php` files |
| `pest` | test files matching staged `.php` sources |
| `oxlint` | staged `.js/.ts/.jsx/.tsx` files |
| `oxfmt` | staged `.js/.ts/.jsx/.tsx` files |
| `vitest` | staged `.js/.ts/.jsx/.tsx` files |

### pre-push (full codebase)

All tools run across the entire project. Additionally, the current branch is
compared against `origin/main` before the suite starts.

| Tool | Scope |
|---|---|
| `rector` | full codebase |
| `pint` | full codebase |
| `phpstan` | full codebase |
| `pest` | full suite |
| `oxlint` | full codebase |
| `oxfmt` | full codebase |
| `vitest` | full suite |

## Tool detection

Tools are discovered in this order:

1. `vendor/bin/<tool>` (Composer local)
2. `node_modules/.bin/<tool>` (npm/yarn/pnpm local)
3. Global `$PATH`

If a tool is not found it is silently skipped — no error is raised.

## Test file resolution

For a staged file like `app/Foo/Bar.php`, devhooks looks for a matching test
in the following locations (first match wins):

```
tests/Foo/BarTest.php
tests/Unit/Foo/BarTest.php
tests/Feature/Foo/BarTest.php
```

If no test file is found the Pest run is skipped for that file.

## Bypassing failed checks

If any check fails, devhooks asks for confirmation instead of aborting silently:

```
  ✗ pre-commit checks failed
  Commit anyway? [y/N]
```

```
  ✗ pre-push checks failed
  Push anyway? [y/N]
```

Answering `y` lets the commit or push proceed despite the failure. Anything
else aborts. This gives you an escape hatch when you need to commit
work-in-progress or push urgently without fixing all issues first.

## Main-divergence check (pre-push)

When pushing from any branch other than `main`, devhooks fetches
`origin/main` and counts commits that are not yet in the current branch.
If any are found, you are asked to confirm before the push continues:

```
  ! origin/main has 3 commit(s) not yet in 'my-feature'
  ! Consider: git fetch origin && git rebase origin/main
  Push anyway? [y/N]
```

To use a different branch name as the integration branch:

```bash
DEVHOOKS_MAIN_BRANCH=master git push
```

## Updating

Re-run `init` after updating the package to refresh the hook files:

```bash
# local install
composer update rokde/devhooks
vendor/bin/devhooks init

# global install
composer global update rokde/devhooks
devhooks init
```

## Project structure

```
bin/
└── devhooks        # Entry point registered in composer "bin"
src/
├── lib.sh          # Shared helpers: colours, JSON parsing, tool detection
├── pre-commit.sh   # pre-commit logic
└── pre-push.sh     # pre-push logic
composer.json
```
