# imageyard

Centralized container image definitions, scoped CI build pipelines, and registry publishing automation.

## Purpose

`imageyard` is the shared home for image-building work. It is intended to collect Dockerfiles, image-specific build assets, CI workflows, publishing rules, runbooks, and decision records for container images that are maintained together.

This repository now includes the Multica runtime image definitions and scoped publish workflows. Additional image projects can be added under their own directories as they are consolidated.

## Expected Structure

Future image work should keep image definitions and supporting files organized by image or source project. Build and publish automation should stay scoped to the images it affects so documentation-only changes or unrelated image changes do not publish images accidentally.

Suggested future layout:

```text
imageyard/
├── .github/
│   └── workflows/
├── multica-runtime/
├── docs/
│   ├── adr/
│   ├── runbooks/
│   └── changelog.md
├── README.md
├── AGENTS.md
└── CLAUDE.md -> AGENTS.md
```

## Current Images

### Multica Runtime

The `multica-runtime/` directory contains two Kubernetes-oriented Multica daemon runtime images:

- Codex runtime: `multica-runtime/codex.Dockerfile`
  - Entrypoint: `multica-runtime/codex-entrypoint.sh`
  - Published tag: `ghcr.io/<owner>/multica-runtime-codex:v0.3.29-codex-0.142.4-r2`
- Claude runtime: `multica-runtime/claude.Dockerfile`
  - Entrypoint: `multica-runtime/claude-entrypoint.sh`
  - Published tag: `ghcr.io/<owner>/multica-runtime-claude:v0.3.29-claude-2.1.197-r2`

Both workflows publish only explicit immutable tags. They do not publish a moving `latest` tag.

## Scoped Publishing

Each Multica runtime image has its own publish workflow. Workflows run on pushes to `main` only when that workflow or that image's Dockerfile/entrypoint changes, and they can also be run manually with `workflow_dispatch`.

## Contributor Guidance

`AGENTS.md` is the canonical shared contributor and agent guidance. `CLAUDE.md` is a compatibility symlink to the same guidance for tools that still look for that path.

Meaningful image, build, publish, or repository convention changes should keep `README.md`, `AGENTS.md`, `docs/changelog.md`, and relevant ADRs or runbooks aligned.
