# pr-comment

Create, update, or remove a **single "marked" comment** on a pull request's
conversation. The action is idempotent: re-running it edits the same comment in
place (found via a hidden HTML marker) and deletes any duplicates, so a PR never
accumulates repeated bot comments. Passing an empty body removes the comment —
handy for reports that should disappear once the underlying condition is fixed.

## Usage

Post/refresh a comment from a rendered Markdown file:

```yaml
permissions:
  pull-requests: write   # required for the action to comment

steps:
  - name: Report something on the PR
    if: ${{ always() && github.event_name == 'pull_request' }}
    uses: analogdevicesinc/shared-actions/pr-comment@main
    with:
      marker: my-report          # unique per bot/report
      body-file: report.md       # empty/missing file => comment removed
```

Or pass the body inline:

```yaml
  - uses: analogdevicesinc/shared-actions/pr-comment@main
    with:
      marker: hello
      body: |
        ### Hello :wave:
        Anything in **Markdown** works here.
```

Remove the comment explicitly (e.g. once a check passes):

```yaml
  - uses: analogdevicesinc/shared-actions/pr-comment@main
    with:
      marker: my-report
      body: ""                   # empty => delete the marked comment
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `marker` | yes | | Unique key; stored as a hidden `<!-- pr-comment:<marker> -->` so later runs find and replace the same comment. |
| `body` | no | `""` | Markdown body. Empty (and no `body-file`) means "ensure absent". |
| `body-file` | no | `""` | Path to a Markdown body file. Wins over `body` when set; a missing/empty file also means "ensure absent". |
| `pr-number` | no | current PR | Pull request number. |
| `repository` | no | `github.repository` | `owner/name`. |
| `token` | no | `github.token` | Token with `pull-requests: write`. |
| `fail-on-error` | no | `false` | Fail the step on an API error. Default warns and succeeds, so a read-only token on a fork PR doesn't break the build. |

## Outputs

| Name | Description |
| --- | --- |
| `comment-id` | ID of the created/updated comment (empty when deleted or none). |
| `result` | `created` \| `updated` \| `deleted` \| `noop`. |

## Notes

- The consuming workflow must grant `permissions: pull-requests: write`.
- The marker is an HTML comment, invisible in the rendered PR.
- Fork PRs triggered by `pull_request` receive a read-only `GITHUB_TOKEN`;
  with the default `fail-on-error: false` the action logs a warning and the job
  still succeeds.
