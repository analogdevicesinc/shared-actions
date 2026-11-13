# Versioning and Releases

To ensure clarity and consistency in managing and consuming shared actions within this repository, we follow the versioning and tagging practices outlined below.

## Versioning

Use [Semantic Versioning](https://semver.org/) for versioning shared actions. Each version consists of three numbers in the format `MAJOR.MINOR.PATCH`:

- `MAJOR`: Introduces backward-incompatible changes (e.g., changes to inputs, outputs, or behavior).
- `MINOR`: Adds backward-compatible features or enhancements.
- `PATCH`: Includes backward-compatible bug fixes or minor improvements.

Examples:

- `v1.0.0`: Initial production quality release.
- `v1.1.0`: Adds a new feature to an existing action.
- `v2.0.0`: Introduces breaking changes.

## Tagging

1. Individual tags for each action: each action in the repository is versioned and tagged independently. Tags are prefixed with the action name.

   Examples:
   - `cloudsmith-auth-v1.0.0`
   - `deb-generator-action-v2.3.1`
   - `pr-comment-v3.0.0`

2. Stable tags for major versions: in addition to specific version tags (`vMAJOR.MINOR.PATCH`), stable tags (`v1`, `v2`, etc.) point to the latest version within a major release series. These stable tags are moved with new minor or patch releases.

   Examples:
   - `cloudsmith-auth-v1` -> `cloudsmith-auth-v1.0.0`
   - `deb-generator-action-v2` -> `deb-generator-action-v2.3.1`

## Release Process

### Update an action's version

When changing an action, determine the appropriate version change using the [Semantic Versioning](#versioning) guidelines above, then update that action's version file:

- Update `package.json` when the action uses one. For example, update `<action-using-ts>/package.json`.
- Otherwise, update the action's `VERSION.ini`, such as `copyright-license-check/VERSION.ini`.

 > **Warning:** Always bump the version when you change an action. Merging into `main` triggers the [auto-tagging workflow](../.github/workflows/auto-tagging.yml); if no version file is changed, the workflow completes without creating a release tag.

### Create a stable tag for major versions - manually

The [auto-tagging workflow](../.github/workflows/auto-tagging.yml) normally handles all tags automatically. Tag manually only as a fallback, for example when:

- The auto-tagging workflow failed or was skipped, leaving a stable tag missing or pointing at the wrong version.
- A stable tag must be repaired or rolled back to an earlier release (for example after a bad release).

Follow the steps below to maintain proper stable tags:

1. To create a new major stable tag, use the commands below:

```bash
git tag -f <action-name>-v1
git push origin <action-name>-v1
```

2. To move an existing stable tag to the latest commit, use the commands below:

```bash
git tag -d <action-name>-v1
git push origin :refs/tags/<action-name>-v1
git tag <action-name>-v1
git push origin <action-name>-v1
```