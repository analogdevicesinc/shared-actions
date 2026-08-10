# Check Clang Format

Action to install and use the **clang-format** tool to format C/C++/Java/JavaScript/JSON/Objective-C/Protobuf/C# code

## What it expects

The source repository is searching for `.clang-format` and `.clangformatignore` files. These are needed for the tool to know what files/paths to ignore and the format to look for.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `source` | no | . | Path location containing the clang-format tool configurations |

## Outputs

The format suggestions and exit status based on findings. Code changes are made during formatting and if diffs are found, it'll prompt `The code is not properly formatted.` with exit code `1`.

## Usage

```yaml
- uses: actions/checkout@v4
  with:
    repository: analogdevicesinc/ADCAM
    path: fru-tools

- uses: analogdevicesinc/shared-actions/check-clang-format@<TAG_VERSION>
  with:
    source: ${{ github.workspace }}
```

## Testing

Located in `tests/` folder.
