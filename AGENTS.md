# imageyard

This file is the canonical shared agent and contributor contract for this repository.

`AGENTS.md` is the source of truth for both Codex and Claude guidance. `CLAUDE.md` is retained as a compatibility symlink to this file for tools that still look for that path.

Centralized repository for container image definitions, CI build pipelines, and registry publishing automation.

## Repository Purpose

This repository is dedicated to image-building work across container images maintained together. It should collect image definitions, image-specific build assets, scoped CI workflows, publishing automation, runbooks, and decision records.

This bootstrap state is documentation-only. There are no active image definitions, build workflows, publish workflows, image tags, or migration contracts in this repository yet.

## Current Repository Structure

```text
imageyard/
├── docs/
│   ├── adr/
│   ├── runbooks/
│   └── changelog.md
├── README.md
├── AGENTS.md
└── CLAUDE.md -> AGENTS.md
```

## Required Git Workflow for All Changes

These steps must be included in every implementation plan unless explicitly told otherwise:

- Create a feature branch from `main` using the `codex/` prefix
  - Example: `git checkout -b codex/<short-feature-name>`
- Keep commits focused and action-oriented
  - Example: `add image build documentation scaffold`
- Do not bundle unrelated refactors with the main change
- Commit focused changes, push the feature branch, and open a draft PR by default unless explicitly told otherwise

## Image Organization Guidance

- Keep image definitions organized by image or source project.
- Keep Dockerfiles, entrypoints, smoke tests, build assets, and runbooks close enough that image ownership is obvious.
- Keep build and publish workflows scoped to the images they affect.
- Use workflow path filters or equivalent guardrails so documentation-only changes and unrelated image changes do not publish images.
- Document the build context, Dockerfile path, supported platforms, registry target, and tag policy when adding an image.
- Keep image tags explicit and immutable by default.
- Avoid moving tags such as `latest`, `stable`, or major/minor aliases unless the tag behavior is explicitly documented in README, changelog, and an ADR or runbook.

## Security and Publishing Guidance

- Do not bake runtime secrets, credentials, tokens, kubeconfigs, cloud credentials, SSH keys, or local developer state into images.
- Do not expose secrets through Docker build args, image labels, workflow logs, README examples, or checked-in config files.
- Runtime credentials should be provided by the deployment platform, secret manager, or user-controlled runtime configuration.
- Keep registry publishing automation explicit about registry, image name, tag set, platforms, and authentication source.
- Prefer image-specific publish workflows over broad repository-wide publish jobs when images have independent release contracts.
- Document any exception to the default immutable-tag policy before publishing.

## Documentation Standards

Every meaningful image, workflow, publishing, or repository convention change should update the relevant docs:

1. `README.md` for repository purpose, current image inventory, and contributor entrypoint changes
2. `AGENTS.md` for the canonical shared agent, workflow, release, and contributor contract
3. `CLAUDE.md` only as the compatibility symlink path for tools that still expect it
4. `docs/changelog.md` for meaningful image, workflow, infrastructure, and documentation changes
5. `docs/runbooks/` when build, smoke-test, publish, release, rollback, or troubleshooting procedures become concrete or materially change
6. `docs/adr/` when architecture, tooling, image layout, tag policy, registry policy, or release decisions and tradeoffs are intentionally locked in

Keep `README.md`, `AGENTS.md`, runbooks, ADRs, and the changelog aligned with implemented behavior.

Self-evaluation checklist:

1. Did I add or change an image contract? If yes, document the Dockerfile path, build context, platforms, tags, and smoke tests.
2. Did I make a durable decision between alternatives? If yes, add or update an ADR.
3. Did I add steps someone must repeat or troubleshoot? If yes, add or update a runbook.
4. Did anything meaningful change? If yes, update the changelog.
5. Did project conventions, tooling, publishing process, or repo context change? If yes, update `AGENTS.md`.
