# Changelog

## 2026-07-01 - Migrate Multica Runtime Images

- Added the Multica Codex and Claude runtime image definitions under `multica-runtime/`.
- Added scoped publish workflows for the Multica runtime images.
- Bumped the migrated image revision tags to `v0.3.29-codex-0.142.4-r2` and `v0.3.29-claude-2.1.197-r2`.
- Updated repository guidance to reflect the first active image contracts.

## 2026-07-01 - Bootstrap Repository Guidance

- Added generic repository documentation for centralized container image definitions, scoped CI build pipelines, and registry publishing automation.
- Added canonical shared contributor and agent guidance in `AGENTS.md`.
- Added ADR and runbook placeholders for future image decisions and repeatable build or publish procedures.
- Documented the default workflow to commit focused changes, push feature branches, and open draft PRs.
- Documented that the current repository state is documentation-only and does not include image definitions, workflows, publishing, tags, or migrations.
