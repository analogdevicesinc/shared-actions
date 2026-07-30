# Reusable Workflows

## Overview

This repository provides a centralized collection of reusable GitHub Actions and
workflows for the **analogdevicesinc** organization. It streamlines common
CI/CD tasks, enforces organizational standards, and reduces duplication across
projects.

## Getting started

Reference a shared action from your workflow using the full repository path and
a ref:

```yaml
- name: Build Debian package
  uses: adi-innersource/reusable-workflows/deb-generator-action@main
  with:
    version: 1.2.3
    working-directory: my-package
```

**Best practices:**

- Pin to a specific tag or ref for stability
- Review the action's README for required inputs, permissions, and environment
  variables
- Test actions in a non-production environment before adopting them in
  production workflows

For contributing new actions or improvements, see the
[Contributing Guide](./CONTRIBUTING.md).

## Available actions

- **[deb-generator-action](deb-generator-action/README.md)**: Build a Debian
  package from source using the standard `packaging/debian/` layout. Reads the
  package name from `debian/control`, fills `@VERSION@`/`@DATE@`/`@ARCHITECTURE@`
  placeholders, auto-installs build dependencies via `mk-build-deps`, and adds
  the ADI package feed (`packages.analog.com`).

More actions will be added over time.

## Getting help

Open an issue in this repository's issue tracker.
