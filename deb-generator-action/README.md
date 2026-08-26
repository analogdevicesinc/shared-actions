# deb-generator-action

A reusable composite action that builds a Debian package from source, following
the standard Analog Devices packaging layout.

## What it expects

The source repository must contain a `packaging/debian/` directory with the
standard debhelper files. The `changelog` uses `@VERSION@`/`@DATE@` placeholders
and the `control` file uses `@ARCHITECTURE@`:

```
packaging/debian/
├── changelog     # first line: pkgname (@VERSION@) UNRELEASED; urgency=low
├── control       # Source: pkgname ; Architecture: @ARCHITECTURE@
├── copyright
├── rules
└── source/format
```

The package name is read automatically from the `Source:` field of
`packaging/debian/control` — you do not pass it as an input.

Build dependencies are installed automatically from the `Build-Depends:` field
of `control` via `mk-build-deps` (the build fails fast if they cannot be
resolved). The action also adds the ADI package feed (`packages.analog.com`,
mirror of Cloudsmith `adi/external`) so ADI-specific packages such as
`libiio-dev` are resolvable.

The `version` input is validated against the Debian upstream-version pattern
(must start with a digit; only `[A-Za-z0-9.+~-]`) and rejected otherwise.

The action does **not** mutate the caller's checked-out workspace: the build
runs in an isolated temporary copy of the source, so `packaging/`, `.git`, and
other files remain untouched for later workflow steps.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version` | yes | — | Version string, e.g. `1.2.3` |
| `working-directory` | no | `.` | Path to the source (relative to `$GITHUB_WORKSPACE`) |
| `control-path` | no | `packaging/debian` | Path to the debian control files/templates (relative to `working-directory`) |
| `ignore-path` | no | `''` | Newline-separated paths to exclude from the orig tarball (beyond `.git` and `debian`) |

## Outputs

| Output | Description |
|--------|-------------|
| `artifact-dir` | Path to the directory containing the built artifacts (`.deb`, `.dsc`, `.debian.tar.xz`, `.orig.tar.gz`) |

## Usage

```yaml
- uses: actions/checkout@v4
  with:
    repository: analogdevicesinc/fru_tools
    path: fru-tools

- uses: adi-innersource/reusable-workflows/deb-generator-action@main
  with:
    version: 8.0.0
    working-directory: fru-tools

- uses: actions/upload-artifact@v4
  with:
    name: fru-tools-deb
    path: ${{ github.workspace }}/artifacts/*
```

### Excluding paths from the source tarball

```yaml
- uses: adi-innersource/reusable-workflows/deb-generator-action@main
  with:
    version: 1.0.0
    working-directory: libm2k
    ignore-path: |
      CI
      .travis.yml
```

## ARM / cross-architecture builds

The composite action runs on the host runner. For arm64/armhf builds, run the
`build-deb.sh` script directly inside a Docker container (it accepts the same
values via the `VERSION`, `WORKING_DIRECTORY`, `CONTROL_PATH`, and `IGNORE_PATH`
environment variables):

```yaml
- name: Build (arm64)
  run: |
    docker run -d --name builder \
      -v "$GITHUB_WORKSPACE/src:/src/src" \
      -v "$GITHUB_WORKSPACE/reusable-workflows:/src/reusable-workflows" \
      -e GITHUB_WORKSPACE=/src \
      arm64v8/debian:trixie sleep infinity
    docker exec \
      -e VERSION=1.0.0 \
      -e WORKING_DIRECTORY=/src/src \
      -e GITHUB_WORKSPACE=/src \
      builder bash /src/reusable-workflows/deb-generator-action/build-deb.sh
```

## Non-standard repositories

Repositories that do not yet follow the `packaging/debian/` +
`@VERSION@`/`@DATE@` convention (older `debian/`-at-root layouts, `envsubst`
`.template` files, AppImage wrappers) must be migrated before they can use this
action. The build script intentionally supports only the one standard pattern.

## Testing

Unit tests use [bats](https://github.com/bats-core/bats-core):

```bash
bats deb-generator-action/tests/build-deb.bats
```
