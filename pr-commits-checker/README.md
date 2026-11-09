# PR Commits Checker

This composite action validates commit messages using [commitlint](https://commitlint.js.org/) and generates a PR comment report with findings.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `base-sha` | no | — | Base SHA for PR range (use `github.event.pull_request.base.sha`) |
| `head-sha` | no | — | Head SHA for PR range (use `github.event.pull_request.head.sha`) |
| `config-path` | no | built-in | Path to custom commitlint config file |
| `fail-on-findings` | no | `true` | Fail the action when any commit has a finding |
| `generate-pr-report` | no | `true` | Generate a pull request comment containing the findings |

When both `base-sha` and `head-sha` are provided, all commits in that range are checked. Otherwise, only the last commit is checked (useful for push events).

## Checks

The built-in configuration enforces:

- Subject line (header) max 50 characters
- Body lines max 72 characters (URLs automatically excluded)
- Blank line between subject and body
- Blank line before trailers
- `Signed-off-by:` trailer required (DCO)

Additional trailers like `Assisted-by:` are allowed and not restricted.

### Example valid commit

```
drivers: frequency: adf4030: add JESD204 support

The ADF4030 generates BSYNC and SYSREF, so it takes part in JESD204
bring-up rather than being configured once at probe.

Assisted-by: Claude Opus 5
Signed-off-by: Name <email@example.com>
```

## Report

When `generate-pr-report` is `true` and findings exist, the action posts a PR comment with a table listing each failing commit and its violations.

## Usage

### Pull request checks

```yaml
name: Check PR commits

on:
  pull_request:

permissions:
  contents: read

jobs:
  check-commits:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Check commit messages
        uses: analogdevicesinc/shared-actions/pr-commits-checker@main
        with:
          base-sha: ${{ github.event.pull_request.base.sha }}
          head-sha: ${{ github.event.pull_request.head.sha }}
```

### Push checks

```yaml
name: Check commits

on:
  push:

permissions:
  contents: read

jobs:
  check-commits:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Check last commit
        uses: analogdevicesinc/shared-actions/pr-commits-checker@main
```

### Custom configuration

To override the built-in rules, provide your own commitlint config:

```yaml
- name: Check commits
  uses: analogdevicesinc/shared-actions/pr-commits-checker@main
  with:
    base-sha: ${{ github.event.pull_request.base.sha }}
    head-sha: ${{ github.event.pull_request.head.sha }}
    config-path: .commitlintrc.js
```
