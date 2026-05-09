# Agent Instructions

## Branch Policy

- **Never push directly to `main`.** All changes, including single-line fixes, must go through a feature branch and a pull request.
- Create a branch from `main` before starting any work. Use a short, descriptive branch name (e.g., `feat/update-checker`, `fix/route-matching`, `chore/bump-version`).
- Commit your changes on the branch. Keep commits focused and use Conventional Commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- When the work is complete, open a pull request against `main`. Wait for CI checks to pass before merging.
- Merge via **squash and merge** or **rebase and merge** to keep the main history linear and clean.

## Pull Requests

- PR title should be a concise summary of the change (under 70 characters).
- PR body should include a brief **Summary** of what changed and a **Test plan** checklist.
- Link any related issues or previous PRs when relevant.
- Do not merge until all CI checks pass.

## Release Process

- Releases are triggered by pushing a `v*` tag (e.g., `v1.0.20`). The CI workflow tests, packages, and publishes the release automatically.
- Before tagging, ensure the version in `Info.plist` (`CFBundleShortVersionString`) matches the tag, the changelog is updated, and the commit is on `main`.
- The tag must point to the `main` branch commit that bumps the version.
