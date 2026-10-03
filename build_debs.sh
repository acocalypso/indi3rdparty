#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

REPO_ROOT=$(pwd)
REPO_DIR="$REPO_ROOT/dist"
DEBS_DIR="$REPO_ROOT/all_debs"
FAILED_PACKAGES=""
BUILT_PACKAGES=""
SKIPPED_PACKAGES=""
DEB_ARCH=$(dpkg --print-architecture)
mkdir -p "$REPO_DIR" "$DEBS_DIR"

export CFLAGS="${CFLAGS:-} -Wno-error"
export CXXFLAGS="${CXXFLAGS:-} -Wno-error"
export DEB_CFLAGS_MAINT_APPEND="${DEB_CFLAGS_MAINT_APPEND:-} -Wno-error"
export DEB_CXXFLAGS_MAINT_APPEND="${DEB_CXXFLAGS_MAINT_APPEND:-} -Wno-error"

[[ -f ./make_deb_pkgs ]] || { echo "Run from the INDI 3rdparty source root." >&2; exit 1; }
chmod +x ./make_deb_pkgs
command -v dpkg-scanpackages >/dev/null || { echo "dpkg-dev is required." >&2; exit 1; }

# Imported MeadeCam SDK depends on Toupcam. Install it before dependent SDKs.
LIBS=$(find . -maxdepth 1 -type d -name 'lib*' ! -name libtoupcam | sed 's|./||' | sort)
if [[ -d libtoupcam ]]; then LIBS="libtoupcam $LIBS"; fi
DRIVERS=$(find . -maxdepth 1 -type d -name 'indi-*' ! -name indi-3rdparty | sed 's|./||' | sort)

record_failure() {
    FAILED_PACKAGES="$FAILED_PACKAGES $1"
    echo "::error::Package build failed: $1"
}

build_and_collect() {
    local target="$1" type="$2"
    if [[ ! -f "debian/$target/rules" ]]; then
        SKIPPED_PACKAGES="$SKIPPED_PACKAGES $target(no-upstream-packaging)"
        return
    fi
    # Upstream supplies only amd64/armhf Ricoh binaries and excludes its SDK
    # from the ARM64 Pentax driver. Do not mislabel a 32-bit binary as ARM64.
    if [[ "$target" == libricohcamerasdk && "$DEB_ARCH" == arm64 ]]; then
        SKIPPED_PACKAGES="$SKIPPED_PACKAGES $target(no-arm64-sdk)"
        return
    fi
    echo ">>> Building $type: $target..."
    local pending=(./*.deb)
    if (( ${#pending[@]} != 0 )); then
        echo "Uncollected packages found before building $target" >&2
        exit 1
    fi
    if ! ./make_deb_pkgs "$target"; then
        record_failure "$target"
        # Quarantine partial output so it cannot be attributed to the next
        # successful target or published in the release.
        local partial=(./*.deb "deb_$target"/*.deb)
        if (( ${#partial[@]} )); then
            mkdir -p "$REPO_ROOT/failed_debs/$target"
            mv "${partial[@]}" "$REPO_ROOT/failed_debs/$target/"
        fi
        return
    fi
    local packages=(./*.deb "deb_$target"/*.deb)
    if (( ${#packages[@]} == 0 )); then
        record_failure "$target(no-debs)"
        return
    fi
    if [[ "$type" == Lib ]]; then
        if ! apt-get install -y --no-install-recommends "${packages[@]}"; then
            record_failure "$target(install)"
        fi
    fi
    mv "${packages[@]}" "$DEBS_DIR/"
    BUILT_PACKAGES="$BUILT_PACKAGES $target"
}

for lib in $LIBS; do build_and_collect "$lib" Lib; done
for drv in $DRIVERS; do build_and_collect "$drv" Driver; done

{
    echo "Built targets:$BUILT_PACKAGES"
    echo "Failed targets:$FAILED_PACKAGES"
    echo "Unsupported or unpackaged targets:$SKIPPED_PACKAGES"
} > "$REPO_ROOT/build-report.txt"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat "$REPO_ROOT/build-report.txt" >> "$GITHUB_STEP_SUMMARY"
fi
cat "$REPO_ROOT/build-report.txt"
if [[ -n "$FAILED_PACKAGES" ]]; then
    echo "::error::Refusing to publish an incomplete package build."
    exit 1
fi
packages=("$DEBS_DIR"/*.deb)
if (( ${#packages[@]} == 0 )); then
    echo "No Debian packages were generated." >&2
    exit 1
fi
cp "${packages[@]}" "$REPO_DIR/"
(cd "$REPO_DIR" && dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz)
