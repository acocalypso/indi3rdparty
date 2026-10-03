#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 INDI_3RDPARTY_SOURCE" >&2
  exit 2
fi
source_root="$(readlink -f "$1")"
[[ -d "$source_root/debian" ]] || exit 1

# Pin external SDK sources so a rebuild does not silently change its ABI.
fetch_source() {
  local repository="$1" revision="$2" target="$3"
  git init "$source_root/$target"
  git -C "$source_root/$target" remote add origin "$repository"
  git -C "$source_root/$target" fetch --depth 1 origin "$revision"
  git -C "$source_root/$target" checkout --detach FETCH_HEAD
}

fetch_source https://github.com/ahp-electronics/libahp-xc.git \
  8561046e7bfac572b24e29d106aeeb39ff933e4b libahp-xc
# Use the INDI packaging rules, which expect a nested source directory.
cp "$source_root/libahp-xc/debian/changelog" "$source_root/debian/libahp-xc/changelog"
cp "$source_root/libahp-xc/LICENSE.md" "$source_root/debian/libahp-xc/copyright"

fetch_source https://github.com/knro/libbno08x.git \
  2f8d6fc70a7f3fb224a46675c7bb9aecae046459 libbno08x
cp -a "$source_root/libbno08x/debian" "$source_root/debian/libbno08x"
# make_deb_pkgs overlays the INDI CMake modules onto each copied source tree.
# Keep BNO08x's version-aware discovery so Trixie's libgpiod v2 API is selected.
cp "$source_root/libbno08x/cmake_modules/FindGPIOD.cmake" "$source_root/cmake_modules/FindGPIOD.cmake"
sed -i 's/dh $@$/dh $@ --buildsystem=cmake --sourcedirectory=libbno08x/' \
  "$source_root/debian/libbno08x/rules"
# Include the pkg-config metadata installed outside the library directory.
echo 'usr/share/pkgconfig/' >> "$source_root/debian/libbno08x/libbno08x-dev.install"

fetch_source https://github.com/raspberrypi/rpicam-apps.git \
  eb293b0552484c35dbddf7788badf42c709a4783 librpicam-app
# Build against Debian's libcamera without Raspberry Pi-only control extensions.
# The INDI driver uses the library; command-line applications are unnecessary.
sed -i "/^subdir('apps')$/d; /^subdir('utils')$/d" "$source_root/librpicam-app/meson.build"
packaging="$source_root/debian/librpicam-app"
mkdir -p "$packaging"
echo 10 > "$packaging/compat"
cat > "$packaging/control" <<'EOF'
Source: librpicam-app
Section: libs
Priority: optional
Maintainer: PINS CI <noreply@github.com>
Build-Depends: debhelper (>= 10), meson, ninja-build, pkg-config, libcamera-dev, libboost-program-options-dev, libexif-dev, libjpeg-dev, libtiff-dev, libpng-dev
Standards-Version: 4.7.0

Package: librpicam-app
Architecture: any
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: rpicam-apps camera library for INDI

Package: librpicam-app-dev
Section: libdevel
Architecture: any
Depends: librpicam-app (= ${binary:Version}), ${misc:Depends}, libcamera-dev
Description: rpicam-apps development headers for INDI
EOF
cat > "$packaging/changelog" <<'EOF'
librpicam-app (1.8.1-1) trixie; urgency=medium

  * Build pinned rpicam-apps for the INDI libcamera driver.

 -- PINS CI <noreply@github.com>  Sat, 03 Oct 2026 12:00:00 +0200
EOF
cat > "$packaging/rules" <<'EOF'
#!/usr/bin/make -f
export DEB_BUILD_OPTIONS = parallel=$(shell nproc)
%:
	dh $@ --buildsystem=meson --sourcedirectory=librpicam-app
override_dh_auto_configure:
	dh_auto_configure -- -Dwerror=false -Ddisable_rpi_features=true -Denable_libav=disabled -Denable_drm=disabled -Denable_egl=disabled -Denable_qt=disabled -Denable_opencv=disabled -Denable_tflite=disabled -Denable_hailo=disabled -Ddownload_hailo_models=false
EOF
cat > "$packaging/librpicam-app.install" <<'EOF'
usr/lib/*/librpicam_app.so.*
usr/lib/*/rpicam-apps-postproc/
usr/share/rpi-camera-assets/
EOF
cat > "$packaging/librpicam-app-dev.install" <<'EOF'
usr/include/
usr/lib/*/librpicam_app.so
usr/lib/*/pkgconfig/
EOF
cp "$source_root/librpicam-app/license.txt" "$packaging/copyright"
find "$source_root/debian" -type f -name rules -exec chmod +x {} +
