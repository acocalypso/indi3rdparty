#!/usr/bin/env bash

set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 INDI_3RDPARTY_SOURCE" >&2
  exit 2
fi

source_root="$(readlink -f "$1")"
debian_root="$source_root/debian"

[[ -d "$debian_root" ]] || {
  echo "Upstream Debian metadata directory not found: $debian_root" >&2
  exit 1
}

# libfli2 and libflipro2 both install 99-fli.rules upstream. Keep the shared
# rule in libfli2 and make the Pro runtime depend on it so the packages remain
# independently functional and can be installed together.
if [[ -f "$debian_root/libfli/libflipro2.install" && -f "$debian_root/libfli/control" ]]; then
  sed -i '\|usr/lib/udev/rules.d/|d' "$debian_root/libfli/libflipro2.install"
  sed -i '/^Package: libflipro2$/,/^Description:/ s/^Depends: ${shlibs:Depends}/Depends: libfli2 (= ${binary:Version}), ${shlibs:Depends}/' \
    "$debian_root/libfli/control"
fi

# These hand-written dependencies use package names removed or renamed in
# Trixie. dpkg-shlibdeps supplies the current libftdi1-2 relationship.
for control in \
  "$debian_root/libqsi/control" \
  "$debian_root/indi-nightscape/control"; do
  if [[ -f "$control" ]]; then
    sed -i 's/, libftdi1\([[:space:]]*$\)/\1/' "$control"
  fi
done

# Trixie exposes the linked client library as libpigpiod-if2-1t64; the old
# explicit dependencies include unavailable package names. The generated
# shlibs dependency supplies the correct current runtime package.
for control in \
  "$debian_root/indi-asi-power/control" \
  "$debian_root/indi-rpi-gpio/control"; do
  if [[ -f "$control" ]]; then
    sed -i 's/, libpigpiod-if2-1, libpigpiod\([[:space:]]*$\)/\1/' "$control"
  fi
done

# The legacy debug package points to the similarly named indi-avalon package
# instead of the runtime produced from its own source package.
if [[ -f "$debian_root/indi-avalonud/control" ]]; then
  sed -i '/^Package: indi-avalonud-dbg$/,/^Description:/ s/^Depends: indi-avalon (/Depends: indi-avalonud (/' \
    "$debian_root/indi-avalonud/control"
fi

echo "Applied Debian Trixie metadata compatibility fixes."
