#!/usr/bin/env bash

set -euo pipefail

if (( $# != 3 )); then
  echo "Usage: $0 PACKAGE VERSION OUTPUT_DIRECTORY" >&2
  exit 2
fi

package_name="$1"
package_version="$2"
output_directory="$(readlink -f "$3")"

[[ "$package_name" =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || {
  echo "Invalid Debian package name: $package_name" >&2
  exit 1
}
dpkg --validate-version "$package_version"
mkdir -p "$output_directory"

package_root="$(mktemp -d)"
trap 'rm -rf "$package_root"' EXIT
mkdir -p "$package_root/DEBIAN"

cat > "$package_root/DEBIAN/control" <<EOF
Package: $package_name
Version: $package_version
Section: misc
Priority: optional
Architecture: all
Maintainer: INDI 3rdparty CI <noreply@github.com>
Description: Validation-only provider for $package_name
 This package exists only during CI dependency resolution. The corresponding
 runtime files were staged from the INDI Core build.
EOF

output_path="$output_directory/${package_name}_${package_version}_all.deb"
dpkg-deb --root-owner-group --build "$package_root" "$output_path" >/dev/null
printf '%s\n' "$output_path"
