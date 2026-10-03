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
2.  Iterates through discovered `lib*` library directories.
3.  Iterates through all `indi-*` drivers.
4.  Uses `make_deb_pkgs` to build each package.
5.  Collects artifacts into a repository structure.
6.  Generates `Packages.gz` for apt consumption.

## Versions and build validation

Both workflows default to upstream INDI core and 3rdparty v2.2.5. The single
`indi-asi-power` workflow also accepts explicit version overrides.

The full build collects failures in its Actions summary and the
`indi-3rdparty-build-report` artifact, then exits unsuccessfully if any supported
package fails to build, produces no packages, or cannot install its libraries.
The installability check also blocks publication on failure.

AHP XC 1.4.7, BNO08x and rpicam-apps 1.8.1 sources are pinned by commit in
`.github/scripts/prepare-source-dependencies.sh` and packaged alongside the
INDI drivers. rpicam-apps builds against Debian's libcamera with Raspberry
Pi-specific extensions disabled. A compiler probe adapts newer exposure controls
to the API available in Debian libcamera. Toupcam builds before MeadeCam, whose SDK
depends on it.

Ricoh's bundled proprietary SDK supports amd64 and armhf only. It is explicitly
excluded from ARM64 builds; the ARM64 Pentax driver builds without it upstream.
Directories without upstream Debian packaging are also listed as exclusions.
Check the build report for the exact supported package set.

## Usage

To use the built packages on your Raspberry Pi (Debian Trixie):

1.  Download the artifacts or release.
2.  Add the folder to your `sources.list` or install manually:
    ```bash
    sudo dpkg -i *.deb
    ```
