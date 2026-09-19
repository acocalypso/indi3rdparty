#!/usr/bin/env bash

set -euo pipefail

if (( $# != 3 )); then
  echo "Usage: $0 DEB_DIRECTORY INDI_CORE_ROOT INDI_RUNTIME_PACKAGE" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=debian-package-helpers.sh
source "$script_dir/debian-package-helpers.sh"

deb_dir="$(readlink -f "$1")"
indi_core_root="$(readlink -f "$2")"
indi_runtime_package="$3"

shopt -s nullglob
debs=("$deb_dir"/*.deb)
if (( ${#debs[@]} == 0 )); then
  echo "No Debian packages found in $deb_dir" >&2
  exit 1
fi

work_root="$(mktemp -d)"
trap 'rm -rf "$work_root"' EXIT

for deb in "${debs[@]}"; do
  package_name="$(dpkg-deb -f "$deb" Package)"
  package_root="$work_root/$package_name"

  echo "Discovering runtime dependencies for $package_name..."
  dpkg-deb -R "$deb" "$package_root"

  existing_depends="$(dpkg-deb -f "$deb" Depends 2>/dev/null || true)"
  generated_depends="$(debian_generate_shlib_depends \
    "$package_name" \
    "$package_root" \
    "$indi_core_root|$indi_runtime_package")"
  final_depends="$(debian_merge_depends "$generated_depends" "$existing_depends")"

  if [[ -n "$final_depends" ]]; then
    debian_control_set_depends "$package_root/DEBIAN/control" "$final_depends"
  fi

  rebuilt="$work_root/$(basename "$deb")"
  dpkg-deb --root-owner-group --build "$package_root" "$rebuilt" >/dev/null
  mv "$rebuilt" "$deb"
  debian_validate_package "$deb"
done

# Check the package set as a unit: drivers may resolve libraries from other
# packages produced by this same workflow.
debian_assert_elf_closure "${debs[@]}" "$indi_core_root"

echo "Dependency generation and ELF closure validation passed for ${#debs[@]} packages."
