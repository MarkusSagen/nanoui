---
name: nanoui-contribution
description: Use when proposing, implementing, reviewing, or preparing an upstream nanoui issue or pull request, especially public APIs or platform backend changes.
---

# Contributing to nanoui

Prepare a contribution that matches nanoui's public contracts, platform support, and review habits. Read the repository `AGENTS.md` and inspect the current base before proposing changes.

## Before implementation

- Verify the feature is still missing: inspect upstream issues, open and merged PRs, recent commits, and the latest release. Check the exact base revision and avoid duplicate proposals.
- Trace the relevant public API through every backend and existing examples. Separate page/webview behavior from native UI behavior; do not imply parity where no backend exists.
- Turn the use case into observable acceptance criteria. Define ownership, callback/data lifetime, threading, cancellation, error reporting, security boundaries, defaults, and compatibility.
- For platform APIs, make a support matrix covering whole-window and embedded/docked use where applicable. Mark each cell implemented, explicitly unsupported, or follow-up, with evidence.

## Implementation and evidence

- Match nearby Zig APIs and architecture. Keep the public contract platform-neutral; put OS-specific work in its backend. Avoid private runtime-class names, downstream patches, and new C/Objective-C shims.
- Add focused platform-free tests plus backend integration tests where the platform can run them. Cross-compilation proves buildability, not runtime behavior; state which was actually exercised.
- Prefer Zig examples and existing headless facilities. Add another language or capture script only when it materially enables a reproducible check and the project accepts that maintenance cost.
- Verify formatting, `zig build lines`, relevant tests, and every platform build required by `AGENTS.md`. Keep files under 600 lines and do not show or drive the developer's screen.
- Report edge cases and remaining support gaps honestly. A screenshot or recording demonstrates appearance, not correctness; include it only when reproducible, hosted, and useful to reviewers.

## Issue and PR readiness

- Issues describe the user problem, current source evidence, desired contract, acceptance criteria, and platform matrix. Mark source findings separately from runtime-verified behavior.
- PRs link the issue with `Fixes #N`, summarize user impact, list API and backend changes, provide test commands/results, and disclose limitations or deferred work. Keep generated media and unrelated artifacts out of source changes.
- Before opening, compare the branch against the current upstream base, inspect the final diff and status, verify the target repository and branch, and confirm no equivalent issue or PR has landed since work began.

## Review a platform claim

- Name the baseline and release separately. Trace the ordinary app entry
  point through the backend rather than inferring behavior from shared types.
- Check ownership, errors, cancellation and teardown. Give each finding a
  user-visible consequence and the smallest repro or test that would close it.
- Record whether the evidence is source inspection, local runtime, CI, or a
  physical device or assistive technology check. Keep these scopes distinct.
- For UI, check keyboard and semantic actions separately from screenshots.
