# check-cpp-format action

Shared action for installing and using the `cppcheck` tool. Used for static analysing of C/C++ code.

## What it expects

The paths for the tool to run, containing C/C++ code. No extra configurations.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `args` | no | --quiet --force --enable=warning,performance,portability,style --std=c++11 | Extra args for the cppcheck commandline tool |
| `paths` | no | `.` | Paths for the cppcheck commandline tool to run |

## Outputs

The findings per file with line code number, type of finding and its description.

## Usage

```yaml
- name: Checkout code
  uses: actions/checkout@v5
  with:
    repository: analogdevicesinc/ADCAM

- uses: adi-innersource/shared-actions/check-cpp-format@1.0.0
  with:
    paths: ${{ github.workspace }}/apps ${{ github.workspace }}/sdk
```
