# INDI 3rd Party Drivers - Debian Build Workflow

This repository contains a GitHub Actions workflow to auto-build INDI 3rd party drivers and libraries as `.deb` packages for ARM64 (Debian Trixie), suitable for Raspberry Pi.

## Workflow Details

The workflow is defined in `.github/workflows/build-arm64.yml`.

### Triggers
- Manual dispatch (`workflow_dispatch`)

### Build Environment
- **OS**: Ubuntu 24.04 ARM64 (native runner)
- **Container**: `debian:trixie` (native ARM64)
- **Architecture**: ARM64

### Artifacts
The workflow produces:
- A directory containing all built `.deb` files.
- A build report listing built, failed, and unpackaged upstream targets.
- A GitHub Release (tag `indi3rdparty-v2.2.5-<run-number>`) with all debs attached.

## Build Script

The build logic is encapsulated in `build_debs.sh`. It:
1.  Installs necessary build dependencies.
2.  Iterates through a discovered `lib*` library directories.
3.  Iterates through all `indi-*` drivers.
4.  Uses `make_deb_pkgs` to build each package.
5.  Collects artifacts into a repository structure.
6.  Generates `Packages.gz` for apt consumption.

## Versions and partial builds

Both workflows default to upstream INDI core and 3rdparty v2.2.5. The single
`indi-asi-power` workflow also accepts explicit version overrides.

The full build continues after individual package failures. A green run can
therefore contain a partial package set. Check the Actions summary and the
`indi-3rdparty-build-report` artifact for omissions. Directories without upstream
Debian rules are skipped explicitly. Libraries requiring external SDKs may still
need additional prerequisites.

## Usage

To use the built packages on your Raspberry Pi (Debian Trixie):

1.  Download the artifacts or release.
2.  Add the folder to your `sources.list` or install manually:
    ```bash
    sudo dpkg -i *.deb
    ```
