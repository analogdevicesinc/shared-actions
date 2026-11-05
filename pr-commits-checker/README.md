# PR Commits Checker

This composite action retrieves the commits in a pull request through the GitHub API and checks each commit message for the conventions below.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `repository` | yes | — | Repository owner and name, in `<OWNER>/<REPO>` format |
| `token` | yes | — | GitHub token used to access the repository and pull request |
| `pr-id` | yes | — | Pull request number |
| `fail-on-findings` | no | `true` | Fail the action when any commit has a finding |
| `generate-pr-report` | no | `true` | Generate a pull request comment containing the findings |

The token needs permission to read pull requests in the target repository. The action does not need a local checkout to inspect commit history.

## Checks

For each pull request commit, the checker flags:

- A first-line commit subject longer than 50 characters.
- A commit body line longer than 72 characters, except lines that start with a space or hyphen, or contain `http` or `https`. The first and final lines are excluded from this check.
- A final commit-message line that does not contain `Signed-off-by`.

The checker records the commit's zero-based position in the pull request, its seven-character SHA, and the first detected reason for that commit. Findings are logged; the action fails for findings when `fail-on-findings` is `true`.

## Report

When `generate-pr-report` is `true`, the action attempts to post a comment using the generated `pr_commits_checker.md` report. The script creates that file only when it finds at least one commit that violates a check.

## Usage

```yaml
name: Check PR commits

on:
  pull_request:

permissions:
  pull-requests: write

jobs:
  check-commits:
    runs-on: ubuntu-latest
    steps:
      - name: Check commit messages
        uses: analogdevicesinc/shared-actions/pr-commits-checker@main
        with:
          repository: ${{ github.repository }}
          token: ${{ secrets.GITHUB_TOKEN }}
          pr-id: ${{ github.event.pull_request.number }}
          fail-on-findings: true
          generate-pr-report: true
```
