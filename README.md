# imageyard

Centralized container image definitions, scoped CI build pipelines, and registry publishing automation.

## Purpose

`imageyard` is the shared home for image-building work. It is intended to collect Dockerfiles, image-specific build assets, CI workflows, publishing rules, runbooks, and decision records for container images that are maintained together.

This bootstrap pass adds repository documentation and contributor guidance only. It does not add image definitions, GitHub Actions workflows, registry publishing, tags, or migrations from other repositories.

## Expected Structure

Future image work should keep image definitions and supporting files organized by image or source project. Build and publish automation should stay scoped to the images it affects so documentation-only changes or unrelated image changes do not publish images accidentally.

Suggested future layout:

```text
imageyard/
├── images/
│   └── <image-name>/
├── .github/
│   └── workflows/
├── docs/
│   ├── adr/
│   ├── runbooks/
│   └── changelog.md
├── README.md
├── AGENTS.md
└── CLAUDE.md -> AGENTS.md
```

The exact layout should be documented when the first image contract is added.

## Contributor Guidance

`AGENTS.md` is the canonical shared contributor and agent guidance. `CLAUDE.md` is a compatibility symlink to the same guidance for tools that still look for that path.

Meaningful image, build, publish, or repository convention changes should keep `README.md`, `AGENTS.md`, `docs/changelog.md`, and relevant ADRs or runbooks aligned.
