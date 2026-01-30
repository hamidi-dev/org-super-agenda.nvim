# Contributing to org-super-agenda.nvim

Thanks for your interest in contributing! 🎉

## Quick Start

1. Fork and clone the repo
2. Make your changes
3. Run the tests (see below)
4. Open a PR!

## Running Tests

```bash
nvim --headless -u tests/helpers/min.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/helpers/min.lua' }"
```

## Code Style

Just follow the existing style:
- Two spaces for indentation
- Snake_case for functions and variables
- Keep it simple and readable

## Commit Messages

Use conventional commits for automatic releases:

```bash
feat: add new feature
fix: fix a bug
docs: update documentation
```

That's it! The CI will run tests automatically when you open a PR.

## Questions?

Open an issue - we're happy to help!
