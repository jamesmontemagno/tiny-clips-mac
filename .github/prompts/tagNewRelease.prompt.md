---
name: tagNewRelease
description: Create a new git tag with release notes extracted from the changelog.
argument-hint: Optional version number to tag (e.g., v1.2.3); if not provided, uses the latest unreleased version from CHANGELOG.md
model: Claude Haiku 4.5 (copilot)
---
# Tag New Release

Create a new annotated git tag for a release based on the current project's changelog.

## Steps:
1. Check the most recent git tags to understand the versioning scheme
2. **Check the app's version setting** (typically in project settings file, build configuration, or Info.plist) — only increment to a new minor version (e.g., 1.3.x → 1.4.0) if the app version has been updated in the codebase; otherwise stay on patch version (e.g., 1.3.2)
3. Read the CHANGELOG.md file to identify the latest unreleased version and its release notes; if they don't exist for that version, create them
4. Update the CHANGELOG.md file to mark the version as released (add the release date if not already set)
5. Verify the git working directory is clean (no uncommitted changes)
6. Create an annotated git tag with:
   - Tag name matching the version (e.g., v1.2.3)
   - Tag message containing the version and formatted release notes from the CHANGELOG
7. Confirm the tag was created successfully by showing the tag details
8. Optionally suggest pushing the tag to origin with `git push origin <tag-name>`

The release notes in the tag message should be cleanly formatted and include all sections (Added, Improved, Fixed, Changed, Deprecated, Removed, Security, etc.) from the CHANGELOG entry for that version.

