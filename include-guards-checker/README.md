# Include Guards Checker

This tool checks for the presence of include guards in header files. Include guards prevent multiple inclusions of the same header file, which can lead to compilation errors.

## What it expects

The paths for the tool to run, containing C/C++ header files.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workspace` | no | `${{ github.workspace }}` | The workspace directory containing the header files |
| `files` | yes | `.` | Header files to check for include guards separated by ',' |
| `generate-pr-report`| no | `false` | Whether to generate a pull request report for the findings |
| `fail-on-findings` | no | `false` | Whether to fail the action if any header files are missing include guards |

## Outputs

The output of this tool is a list of header files that are missing include guards. Additionally, if `generate-pr-report` is set to `true`, a pull request report will be generated for the findings.

## Usage

```yaml
- name: Checkout code
  uses: actions/checkout@v5
  with:
    repository: analogdevicesinc/no-OS

- uses: adi-innersource/shared-actions/include-guards-checker@1.0.0
  with:
    workspace: ${{ github.workspace }}
    generate-pr-report: true
    fail-on-findings: true
    files: projects/ad9083/src/app_ad9083.h,projects/ad9081/src/app_clock.h
```
