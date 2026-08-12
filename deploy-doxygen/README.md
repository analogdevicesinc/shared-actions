# deploy-doxygen action

Action to setup and deploy documentation using `doxygen` tool to `github-pages`. 

## What it expects

A folder containing documentation under root repository path.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `work_dir` | no | `.` | ${{ github.workspace }} |
| `docs_dir` | yes | `-` | Path to documentation directory |
| `version` | no | `1.13.2` | Doxygen tool version |
| `args` | no | `-` | Extra arguments for doxygen build |
| `publish` | no | `true` | Condition to publish the docs to github pages or not  |

## Outputs

| Output | Description |
|--------|-------------|
| `artifact-dir` | Path to the directory containing the built artifacts (`.deb`, `.dsc`, `.debian.tar.xz`, `.orig.tar.gz`) |

## Usage

```yaml
- uses: actions/checkout@v5
  with:
    repository: analogdevicesinc/ADCAM
    path: ADCAM

- uses: analogdevicesinc/shared-actions/deploy-doxygen@1.0.0
  with:
    work_dir: ${{ github.workspace }}
    docs_dir: ${{ github.workspace }}/doc
    args: evalkit-doc
    version: 1.8.15
    publish: ${{ github.event_name == 'pull_request' && 'false' || github.event_name == 'push' && 'true' }}
```
