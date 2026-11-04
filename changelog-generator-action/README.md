# changelog-generator-action

A reusable composite action that regenerates the `debian/changelog` bullet
entries from git commit history, **in place**. It never commits, pushes, or
opens a PR — it only rewrites the changelog file so a later step (or you) can
review and commit it.

## What it does

- Collects commit subjects for a configurable range (`since..until`). With no
  `since`, it uses the most recent reachable tag (`git describe --tags`); with
  no tag, the whole history. With no `until`, it uses `HEAD`.
- Reads the package name and maintainer from the `Source:` / `Maintainer:`
  fields of `packaging/debian/control` (same source of truth as
  `deb-generator-action`).
- Updates the changelog **leaving `@VERSION@` and `@DATE@` untouched** so
  `deb-generator-action` still fills them at build time:
  - If the top stanza is still a template (version `@VERSION@`), its bullets
    are **overwritten in place** and the rest of the file is kept.
  - If the top stanza is a real, released entry, a new template stanza is
    **prepended** above the existing history.

## What it expects

```
packaging/debian/
├── changelog     # first line: pkgname (@VERSION@) <dist>; urgency=low
└── control       # Source: pkgname ; Maintainer: Name <email-or-url>
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `working-directory` | no | `.` | Path to the source (relative to `$GITHUB_WORKSPACE`) |
| `control-path` | no | `packaging/debian` | Path to the debian control files (relative to `working-directory`) |
| `distribution` | no | `kuiper` | Changelog distribution field |
| `since` | no | *(last tag)* | Start of the commit range (exclusive). Empty = last reachable tag, or whole history if none |
| `until` | no | `HEAD` | End of the commit range (inclusive) |

The package name and maintainer come from `control`; the entry format
(`  * <subject>`) is fixed internally and is not an input.

## Outputs

| Output | Description |
|--------|-------------|
| `entries-count` | Number of changelog entries generated (0 = file left unchanged) |

## Usage

```yaml
jobs:
  update-changelog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0      # REQUIRED: full history for the commit range
          fetch-tags: true    # REQUIRED: tags for `git describe`
      - uses: analogdevicesinc/shared-actions/changelog-generator-action@main
        with:
          since: v1.2.0       # optional; omit to use the last tag
      # the changelog is now updated on disk — commit it in a later step
```

## Notes

- **Checkout must be deep.** `actions/checkout` defaults to a shallow clone
  with no tags, which breaks `git describe`. Always set `fetch-depth: 0` and
  `fetch-tags: true`.
- **Version/date.** This action never writes the version or date — it keeps the
  `@VERSION@`/`@DATE@` placeholders for `deb-generator-action`.
