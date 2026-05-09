# Claude Code Instructions

## Branch Workflow (mandatory)

1. **Always create a new branch from `main` before making any changes.** Never edit files directly on `main`.
   ```bash
   git checkout -b feat/<short-description>
   # or: git checkout -b fix/<short-description>
   # or: git checkout -b chore/<short-description>
   ```
2. Commit your changes on the branch with Conventional Commit messages.
3. Push the branch and open a pull request against `main`:
   ```bash
   git push -u origin HEAD
   gh pr create --title "..." --body "$(cat <<'EOF'
   ## Summary
   ...

   ## Test plan
   - [ ] ...
   EOF
   )"
   ```
4. Wait for CI checks to pass and the review to clear (no P0/P1 findings), then squash-merge the PR.
5. After merging, switch back to `main`, pull, and delete the local branch.

## Version Bumps and Releases

- Version is tracked in `Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`).
- To release: bump the version in `Info.plist`, update `CHANGELOG.md`, commit on `main`, then create and push a `vX.Y.Z` tag.
- The CI `release.yml` workflow triggers on tag push and handles DMG packaging and GitHub release publishing.
- Tag must always point to a commit on `main`.

## Project Structure

- `Sources/GatewayProxyCore/` — shared proxy logic, provider profiles, settings model
- `Sources/GatewayProxy/` — gateway proxy executable
- `Sources/ClaudeGateway/` — macOS SwiftUI manager app (the main deliverable)
- `Tests/` — unit tests
- `scripts/package_dmg.sh` — builds the app and creates a DMG; reads version from `Info.plist`
- `site/` — public-facing Vercel website

## Running

- Build: `swift build -c release`
- Test: `swift test`
- Package DMG: `./scripts/package_dmg.sh`
