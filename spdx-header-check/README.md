# SPDX Header Check

A GitHub Action that scans source files for [SPDX](https://spdx.dev/) copyright and license headers, and validates copyright years against Git history.

## Expected Header Format

Every source file should contain two SPDX tags:

```python
# SPDX-FileCopyrightText: 2026 Analog Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
```

Year ranges are used when a file has been modified across multiple years:

```python
# SPDX-FileCopyrightText: 2020-2026 Analog Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
```

For custom or proprietary licenses, use `LicenseRef-` identifiers:

```python
# SPDX-FileCopyrightText: 2026 Analog Devices, Inc.
#
# SPDX-License-Identifier: LicenseRef-ADI-Proprietary
```

Place the full license text in `LICENSES/LicenseRef-ADI-Proprietary.txt` in your repository.

## Usage

| Event | `full-scan` | Behavior |
|-------|-------------|----------|
| `pull_request` | `false` (default) | Scans changed files only |
| `pull_request` | `true` | Scans entire repository |
| `push` / `workflow_dispatch` | `false` (default) | Skips scan |
| `push` / `workflow_dispatch` | `true` | Scans entire repository |

### Default (PR mode, changed files only)

```yaml
name: SPDX Header Check
on: [pull_request]

jobs:
  spdx-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: analogdevicesinc/shared-actions/spdx-header-check@main
```

### Full Repository Scan

```yaml
- uses: analogdevicesinc/shared-actions/spdx-header-check@main
  with:
    full-scan: true
```

### Report-Only Mode (non-blocking)

```yaml
- uses: analogdevicesinc/shared-actions/spdx-header-check@main
  with:
    fail-on-missing: false
```

### Restrict to Specific Licenses

```yaml
- uses: analogdevicesinc/shared-actions/spdx-header-check@main
  with:
    valid-licenses: 'Apache-2.0,MIT,BSD-3-Clause'
```

Files with a license identifier not in this list will be flagged.

### Using `.spdx-config.yml` (recommended for repos with mixed licenses)

Instead of passing `valid-licenses` in the workflow, create a `.spdx-config.yml` in the repo root:

```yaml
# The repo's primary license
project-license: Apache-2.0

# Additional licenses allowed in individual files (e.g., vendored code)
allowed-licenses:
  - MIT           # third-party utility from project X
  - BSD-3-Clause  # imported driver code
  - LicenseRef-ADI-Proprietary  # internal components
```

The action auto-detects the repo license from the `LICENSE` file and merges it with the allowlist. You don't need to pass anything in the workflow:

```yaml
- uses: analogdevicesinc/shared-actions/spdx-header-check@main
```

### Custom File Extensions

```yaml
- uses: analogdevicesinc/shared-actions/spdx-header-check@main
  with:
    file-extensions: 'py,sh,groovy,tcl,pl'
```

### Copyright-Only (no license check)

```yaml
- uses: analogdevicesinc/shared-actions/spdx-header-check@main
  with:
    license-pattern: ''
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `scan-path` | Root path to scan for source files | `.` |
| `file-extensions` | Comma-separated list of file extensions to scan (without dots) | See [Supported Languages](#supported-languages) |
| `exclude-dirs` | Comma-separated list of additional directories to exclude | `''` |
| `ignore-file` | Path to ignore patterns file (like `.gitignore`) | `.spdxignore` |
| `fail-on-missing` | Fail the action if files have SPDX header issues | `true` |
| `summary-output` | Whether to output a GitHub Actions job summary | `true` |
| `full-scan` | Scan all files. When `false`, only scan changed files in PR | `false` |
| `copyright-pattern` | Regex to match the copyright line (must have year capture groups) | `SPDX-FileCopyrightText:\s+(\d{4})(-(\d{4}))?\s+.+` |
| `license-pattern` | Regex to match the license line. Empty to skip license checking | `SPDX-License-Identifier:\s+\S+` |
| `license-header-lines` | Number of lines from top of file to scan for license | `30` |
| `valid-licenses` | Comma-separated list of accepted SPDX identifiers. Merged with `.spdx-config.yml`. Empty to accept any | `''` |
| `spdx-config` | Path to YAML config file defining project-license and allowed-licenses | `.spdx-config.yml` |

## Outputs

| Output | Description |
|--------|-------------|
| `total-files-scanned` | Total number of source files scanned |
| `files-missing-copyright` | Number of files missing SPDX-FileCopyrightText |
| `files-wrong-years` | Number of files with incorrect copyright years |
| `files-missing-license` | Number of files missing SPDX-License-Identifier |
| `files-invalid-license` | Number of files with a license identifier not in the valid-licenses list |
| `missing-files-list` | Newline-separated list of files missing copyright |
| `wrong-years-list` | Newline-separated list of files with wrong years |
| `missing-license-list` | Newline-separated list of files missing license |
| `invalid-license-list` | Newline-separated list of files with invalid license |
| `ignored-files-list` | Newline-separated list of ignored files |
| `detected-license` | SPDX identifier auto-detected from the repo LICENSE file (empty if not detected) |
| `passed` | `true` if all scanned files have valid SPDX headers |

## Repo License Auto-Detection

The action automatically detects the repository's license from the `LICENSE`, `LICENSE.md`, `LICENSE.txt`, `COPYING`, or `COPYING.md` file. Detection works two ways:

1. **SPDX identifier**: if the file contains `SPDX-License-Identifier: <id>`, that identifier is used directly
2. **Text matching**: common license texts (Apache-2.0, MIT, GPL, BSD, MPL, ISC) are recognized from their headers

The detected license is shown in the job summary and is automatically added to the allowed licenses list (if an allowlist is active). If detection fails, add `SPDX-License-Identifier:` to your LICENSE file or set the license explicitly in `.spdx-config.yml`.

## `.spdx-config.yml`

Create this file in your repo root to define which licenses are allowed:

```yaml
# The repo's primary license (overrides auto-detection)
project-license: Apache-2.0

# Additional licenses allowed in individual files
allowed-licenses:
  - MIT           # vendored utility
  - BSD-3-Clause  # imported driver code
  - LicenseRef-ADI-Proprietary  # internal components
```

The allowlist is merged from three sources (all optional):
1. `project-license` from `.spdx-config.yml`
2. `allowed-licenses` from `.spdx-config.yml`
3. `valid-licenses` action input
4. Auto-detected repo license (added automatically if any allowlist is active)

If none of these are set, any `SPDX-License-Identifier` is accepted.

## Copyright Year Validation

The copyright year range must reflect the file's Git history:

- **Start year**: year of the first commit that introduced the file
- **End year**: year of the most recent commit that touched the file
- **Single year**: when first and last commit are in the same year, the header must use single-year format (not a range)

Git history follows file renames (`git log --follow`). Copy operations are treated as new files.

Requires `fetch-depth: 0` in your checkout step for full Git history access.

## Ignore File (`.spdxignore`)

Create a `.spdxignore` file in your repository root to exclude files from scanning. Uses gitignore syntax:

```gitignore
# Ignore specific files
LICENSE
README.md

# Ignore patterns
*.md
*.json
test/**/*.js

# Ignore directories
docs/
examples/
third_party/
```

## Supported Languages

The action scans the following file extensions by default:

- **JavaScript/TypeScript**: js, ts
- **Python**: py
- **Java**: java
- **C/C++**: c, h, cpp, hpp
- **C#**: cs
- **Go**: go
- **Rust**: rs
- **Ruby**: rb
- **PHP**: php
- **Shell**: sh
- **PowerShell**: ps1

## Default Excludes

The following directories are always excluded:

- `node_modules`
- `dist`
- `build`
- `.git`

## License

This action is licensed under Apache 2.0. See [LICENSE](../LICENSE).
