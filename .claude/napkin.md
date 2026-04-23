# Napkin Runbook

## Curation Rules
- Re-prioritize on every read.
- Keep recurring, high-value notes only.
- Max 10 items per category.
- Each item includes date + "Do instead".

## Execution & Validation (Highest Priority)
1. **[2026-04-23] Git object corruption can break diff while status still works**
   Do instead: run `git fsck --full`, fetch remotes/submodules, then restore any missing unchanged blobs with `git hash-object -w <file>`.
2. **[2026-04-23] Git status can hang when submodule scans are unhealthy**
   Do instead: diagnose with `git status -uno` first, then inspect untracked-heavy directories before running full status.

## Shell & Command Reliability
1. **[2026-04-23] Prefer bounded diagnostics for uncertain Git commands**
   Do instead: use focused commands like `git branch --show-current`, `git remote -v`, and traced status variants before broader Git operations.

## Domain Behavior Guardrails

## User Directives
