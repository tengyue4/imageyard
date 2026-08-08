# Multica Runtime Release Runbook

Use this runbook to upgrade, validate, publish, verify, or roll back the Multica Codex and Claude runtime images. Keep all work in ImageYard; Kubernetes and GitOps wiring is a separate change.

## Release Inputs

Choose the latest stable, non-prerelease Multica release and verify that its `multica-backend` image contains both `linux/amd64` and `linux/arm64`. Use npm's `latest` dist-tag for Codex after excluding prereleases. Use Anthropic's deliberately delayed `stable` release channel for Claude Code.

The image tag format is:

```text
v<MULTICA>-codex-<CODEX>-r<REVISION>
v<MULTICA>-claude-<CLAUDE>-r<REVISION>
```

Reset the revision to `r1` when either component version changes. Before editing and again before publishing, inspect the complete target image reference. If it resolves, choose a new revision; never overwrite it.

## Local Validation

Validate shell and workflow syntax first:

```sh
sh -n multica-runtime/codex-entrypoint.sh
sh -n multica-runtime/claude-entrypoint.sh
ruby -e 'require "yaml"; ARGV.each { |path| YAML.parse_file(path) }' \
  .github/workflows/publish-multica-runtime-codex.yml \
  .github/workflows/publish-multica-runtime-claude.yml
```

Build each image from the repository root on an ARM64 Docker host:

```sh
docker buildx build --pull --platform linux/arm64 --load \
  --file multica-runtime/codex.Dockerfile \
  --tag imageyard/multica-runtime-codex:smoke \
  multica-runtime

docker buildx build --pull --platform linux/arm64 --load \
  --file multica-runtime/claude.Dockerfile \
  --tag imageyard/multica-runtime-claude:smoke \
  multica-runtime
```

For each image, override the entrypoint and verify:

- `multica --version` and the provider's `--version` output match the pinned versions.
- `id -u` is not `0`.
- `git`, `gh`, `ssh`, `node`, `npm`, and the provider CLI resolve on `PATH`.
- `bwrap` resolves in the Codex image; `rg` resolves in the Claude image.
- `multica daemon start --help` still exposes the entrypoint's foreground, identity, concurrency, and no-auto-update flags.
- Multica v0.4.21 accepts `--server-url` but omits it from `daemon start` help, so also run an unauthenticated parser probe containing every entrypoint flag and require a post-parse authentication error rather than an unknown-flag error.

Run each image through its normal entrypoint without required variables, then add only dummy marker values one at a time. Every run must fail before daemon launch, name only the next missing variable, and never print a marker value. Do not use real credentials in smoke tests.

## Publish and Verify

Merge a focused pull request into `main`. Each image workflow publishes its single immutable tag only when its own workflow, Dockerfile, or entrypoint changes. The workflow serializes publishes for that image and uses authenticated GHCR manifest inspection to refuse an existing tag or fail closed when tag availability cannot be verified.

Follow both Actions runs until they succeed. Then inspect each published reference with `docker buildx imagetools inspect`. Record:

- the top-level OCI image-index digest;
- the `linux/amd64` manifest digest;
- the `linux/arm64` manifest digest.

Ignore `unknown/unknown` BuildKit attestation manifests when selecting platform digests. Run the lightweight version, user, and tool checks again against the published ARM64 image.

## Rollback

Published tags are immutable. Roll back consumers by selecting a previously verified immutable tag or digest in the separate GitOps repository. Do not move, replace, or delete a published ImageYard release tag as part of rollback, and do not deploy from this repository.
