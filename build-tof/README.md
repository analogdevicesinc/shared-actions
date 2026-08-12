# check-cpp-format action

Shared action for installing dependencies and building for TOF related projects.

## What it expects

A specific repository from the TOF projects. 
Currently existing:
  - https://github.com/analogdevicesinc/ToF
	- https://github.com/analogdevicesinc/libaditof
	- https://github.com/analogdevicesinc/ADCAM
  - https://github.com/analogdevicesinc/ToF-drivers

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `source-path` | no | `.` | Path of the source to be build |
| `default-cmake-flags` | no | -DWITH_NETWORK=1 -DWITH_PYTHON=1 -DWITH_OPENCV=1 -DWITH_EXAMPLES=1 -DWITH_DOC=0 -DWITH_OPEN3D=0 -DCI_BUILD=1 | Default arguments for the cmake build|
| `extra-cmake-flags` | no | ` ` | Extra arguments for the cmake build |
| `build-type` | no | default | Type of build - default(linux), docker or windows |

## Outputs

The build process of the TOF project with its cmake and make logs.

## Usage

```yaml
- name: Checkout code
  uses: actions/checkout@v5
  with:
    repository: analogdevicesinc/ADCAM

- uses: adi-innersource/shared-actions/build-tof@main
  with:
    source-path: ${{ github.workspace }
    build-type: docker
```
