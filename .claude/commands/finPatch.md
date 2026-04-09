---
description: Finalize the current patch release with version bump, docs updates, commit, push, and release-tag push
argument-hint: "[optional release note or scope hint]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
  - AskUserQuestion
  - SlashCommand
---

Run the `finPatch` patch-release workflow for this repository.

Always begin by loading the project rules:
- @AGENTS.md

Use `$ARGUMENTS` only as optional context for changelog framing, release-note wording, or commit wording.

Core operating rules for this workflow:
- Work thoroughly and precisely.
- Keep it simple.
- Do research when release state, tooling behavior, or documentation state is unclear.
- Do not guess the current version, tag state, or release status.
- Do not hide unresolved bugs; document them explicitly.
- Do not claim that known problems are solved if they are merely improved.
- Before answering or declaring completion, apply the must-obey rule from `AGENTS.md`:
  - `Did I really think through everything?`

Repository-specific release sources of truth:
- `project.yml` for `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
- `CHANGELOG.md` for versioned release history
- `.plans/01-initial-plan.md` for postmortem, no-gos, current known issues, and errors that must not be repeated
- `README.md` for user-facing release notes, Gatekeeper status, and known limitations
- `.github/workflows/release.yml` for tag-triggered DMG release automation

Execution flow:
1. Read `AGENTS.md`.
2. Inspect:
   - `project.yml`
   - `CHANGELOG.md`
   - `.plans/01-initial-plan.md`
   - `README.md`
   - `.github/workflows/release.yml`
   - `git status`
   - `git tag --sort=-version:refname`
3. Determine the current release state from evidence:
   - current marketing version in `project.yml`
   - current build number in `project.yml`
   - latest release entry in `CHANGELOG.md`
   - latest git tag
4. Validate the state before editing:
   - if `project.yml`, `CHANGELOG.md`, and latest tag disagree, surface the exact mismatch
   - do not silently continue through an ambiguous release state
5. Calculate the next patch version by incrementing only the patch segment.
6. Increment the build number by `1`.
7. Update `project.yml` with:
   - new `MARKETING_VERSION`
   - new `CURRENT_PROJECT_VERSION`
8. Run `xcodegen generate`.
9. Update documentation comprehensively:
   - `CHANGELOG.md`
     - add a new top release entry with the current date
     - document what actually changed
     - include `Known Issues` when problems remain
   - `README.md`
     - update displayed version
     - update release/tag examples
     - document Gatekeeper state prominently if it changed or still matters
     - document known user-facing limitations prominently if they remain
   - `.plans/01-initial-plan.md`
     - update version snapshot
     - record newly discovered problems, mistakes, regressions, and no-gos
     - add or update concrete rules about what must not happen again
     - document current unresolved limitations honestly
   - `.github/workflows/release.yml`
     - update only if release automation behavior or release constraints actually changed
10. If release behavior changed in a meaningful way, update any other directly affected docs instead of leaving them stale.
11. Verify before committing:
   - re-read the changed version fields
   - re-read the new top of `CHANGELOG.md`
   - re-read the updated known-limitations sections in `README.md` and `.plans/01-initial-plan.md`
12. Run both test paths:
   - full local suite:
     - `xcodebuild -project MKVQuickLook.xcodeproj -scheme MKVQuickLook -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`
   - release-style suite:
     - `xcodebuild -project MKVQuickLook.xcodeproj -scheme MKVQuickLook -configuration Debug -destination 'platform=macOS' -skip-testing:MKVQuickLookTests/RendererSmokeTests CODE_SIGNING_ALLOWED=NO test`
13. If code affecting installed behavior changed, reinstall locally with:
   - `./scripts/install-local.sh`
14. Inspect `git diff --stat` and `git status` before committing.
15. Commit intentionally:
   - use one coherent release commit unless there are clearly unrelated groups
   - commit message must state the new release version
16. Push `main`:
   - `git push origin main`
17. Create the new patch tag from the committed state:
   - `git tag vX.Y.Z`
18. Push the tag:
   - `git push origin vX.Y.Z`
19. Report completion with:
   - old version -> new version
   - old build -> new build
   - whether `README.md`, `CHANGELOG.md`, `.plans/01-initial-plan.md`, and workflow/docs changed
   - test results from both test paths
   - commit hash and subject
   - tag pushed
   - reminder that the DMG appears on GitHub Releases only after the GitHub Actions release workflow finishes

Rules for documenting problems and errors:
- Document mistakes that actually happened, not just the final polished state.
- If a bug was improved but not eliminated, write that plainly.
- If a regression was caused by a specific bad change or bad assumption, record that in `.plans/01-initial-plan.md`.
- Do not remove earlier lessons just because the latest release is cleaner.

Git rules:
- Do not tag before `main` is pushed cleanly.
- Do not reuse an old release tag for a new commit.
- Always create a new patch tag for a new release commit.
- Do not include unrelated working-tree changes in the release commit.

Behavior rules:
- If `$ARGUMENTS` is empty, continue anyway.
- This workflow is not complete until version bump, documentation, verification, commit, `main` push, tag creation, and tag push are all done.
