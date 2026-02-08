# INDI 3rd Party Drivers - Debian Build Workflow

This repository contains a GitHub Actions workflow to auto-build INDI 3rd party drivers and libraries as `.deb` packages for ARM64 (Debian Trixie), suitable for Raspberry Pi.

## Workflow Details

The workflow is defined in `.github/workflows/build-arm64.yml`.

### Triggers
- Pushes to `main`
- Pull Requests
- Manual dispatch (`workflow_dispatch`)

### Build Environment
- **OS**: Ubuntu Latest (Runner)
- **Container**: `debian:trixie` (ARM64 via QEMU)
- **Architecture**: ARM64

### Artifacts
The workflow produces:
- A directory containing all built `.deb` files.
- A `Packages.gz` and `Release` file, making it a valid apt repository.
- A GitHub Release (tag `arm64-build`) with all debs attached.

## Build Script

The build logic is encapsulated in `build_debs.sh`. It:
1.  Installs necessary build dependencies.
2.  Iterates through a predefined list of libraries (`LIBS`).
3.  Iterates through all `indi-*` drivers.
4.  Uses `make_deb_pkgs` to build each package.
5.  Collects artifacts into a repository structure.
6.  Generates `Packages.gz` for apt consumption.

## Usage

To use the built packages on your Raspberry Pi (Debian Trixie):

1.  Download the artifacts or release.
2.  Add the folder to your `sources.list` or install manually:
    ```bash
    sudo dpkg -i *.deb
    ```
