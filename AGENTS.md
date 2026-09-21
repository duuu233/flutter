# Project AI Instructions

## Project Context

This project is maintained across multiple development environments:

- Office computer
- Home computer
- Remote SSH servers

Git repository is the single source of truth.

Do not assume local machine state is shared between environments.

The project may be modified from different computers at different times.

Always consider synchronization and compatibility with other development environments.

---

# AI Working Principles

The AI assistant should act as a long-term project collaborator.

Before making changes:

1. Understand the existing implementation.
2. Check dependencies and impact.
3. Avoid unnecessary changes.
4. Preserve existing design decisions.

Prefer understanding before modifying.

---

# Dependencies and Toolchain

Toolchain baseline: **Flutter 3.44.x stable (Dart 3.12.x)** — decided by the project owner on
2026-09-21. Unless a change is proven necessary (a concrete blocking build/store error, a feature that
explicitly requires it, or a store policy), do **not**:

- upgrade Flutter or switch channels;
- run `flutter pub upgrade` or bump dependency versions; use `flutter pub get` only;
- add `dependency_overrides`;
- change iOS/Android build environment settings (Podfile platform, `IPHONEOS_DEPLOYMENT_TARGET`,
  SwiftPM switch, Gradle/AGP/Kotlin/compileSdk).

If `flutter pub get` rewrites `pubspec.lock` without an intended dependency change, do not commit it;
the local Flutter version is almost certainly off-baseline. Rules, the reasoning, and the pending
rollback of `219ad59` are in `docs/runbooks/BUILD_RELEASE.md` §〇.6–〇.7.

---

# CodeGraph Usage

This project uses CodeGraph as the primary code intelligence system.

Use CodeGraph first when analyzing:

- project architecture
- module relationships
- dependencies
- function call chains
- class relationships
- impact of changes
- refactoring scope
- unfamiliar code

Do not rely only on text search when structural understanding is required.

Examples:

Use CodeGraph for questions like:

- "Who calls this function?"
- "What modules depend on this?"
- "What will be affected if this changes?"
- "Explain this subsystem architecture."

---

# CodeGraph Management

CodeGraph represents the current state of the codebase.

CodeGraph contains:

- project structure
- files
- symbols
- functions/classes
- dependencies
- callers/callees
- impact relationships

## Local Index Rules

The `.codegraph/` directory is a local generated index.

Rules:

- Never commit `.codegraph/` to Git.
- Each computer maintains its own CodeGraph index.
- The index can always be regenerated.
- Do not depend on another machine's `.codegraph/` data.

The project Git repository contains source and knowledge, not CodeGraph cache.

---

# CodeGraph Synchronization

After pulling code changes from Git:

Run:

```bash
codegraph sync
```
