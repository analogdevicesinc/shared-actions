# PR Commits Checker

This composite action validates commit messages and generates a PR comment report with findings.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `repository` | yes | — | Repository to check commits in, in `<OWNER>/<REPO>` format |
| `token` | yes | — | Github token necessary for accessing the API to make requests about commits history |
| `pr-id` | yes | — | Pull request id for the work in progress |
| `fail-on-findings` | no | `true` | Condition whether to fail or not on findings |
| `generate-pr-report` | no | `true` | Condition to whether create a pr comment with a report on findings or not |

All commits of the pull request are checked.

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
          repository: ${{ github.repository }}
          token: ${{ secrets.GITHUB_TOKEN }}
          pr-id: ${{ github.event.pull_request.number }}
          fail-on-findings: true
          generate-pr-report: true
```
