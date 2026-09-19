#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/debian/libfli" \
  "$fixture/debian/libqsi" \
  "$fixture/debian/indi-nightscape" \
  "$fixture/debian/indi-asi-power" \
  "$fixture/debian/indi-rpi-gpio"

cat > "$fixture/debian/libfli/libflipro2.install" <<'EOF'
usr/lib/*/libflipro.so.2*
usr/lib/*/libflialgo.so.2*
usr/lib/udev/rules.d/
EOF

cat > "$fixture/debian/libfli/control" <<'EOF'
Package: libfli2
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: Standard FLI library

Package: libflipro2
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: FLI Pro library
EOF

for control in libqsi indi-nightscape; do
  cat > "$fixture/debian/$control/control" <<'EOF'
Package: test-ftdi
Depends: ${shlibs:Depends}, ${misc:Depends}, libftdi1
Description: FTDI test package
EOF
done

for control in indi-asi-power indi-rpi-gpio; do
  cat > "$fixture/debian/$control/control" <<'EOF'
Package: test-pigpio
Depends: ${shlibs:Depends}, ${misc:Depends}, libpigpiod-if2-1, libpigpiod
Description: pigpio test package
EOF
done

# Applying the compatibility patch twice must not duplicate relationships.
"$script_dir/patch-upstream-debian-metadata.sh" "$fixture"
"$script_dir/patch-upstream-debian-metadata.sh" "$fixture"

if grep -q 'usr/lib/udev/rules.d/' "$fixture/debian/libfli/libflipro2.install"; then
  echo "Duplicate FLI udev rule was not removed" >&2
  exit 1
fi

expected='Depends: libfli2 (= ${binary:Version}), ${shlibs:Depends}, ${misc:Depends}'
if [[ "$(grep -Fc "$expected" "$fixture/debian/libfli/control")" -ne 1 ]]; then
  echo "libflipro2 dependency correction is missing or duplicated" >&2
  exit 1
fi

if grep -R -E '^Depends:.*(, libftdi1|, libpigpiod-if2-1|, libpigpiod)(,|$)' \
  "$fixture/debian/libqsi/control" \
  "$fixture/debian/indi-nightscape/control" \
  "$fixture/debian/indi-asi-power/control" \
  "$fixture/debian/indi-rpi-gpio/control"; then
  echo "An obsolete Trixie dependency remains" >&2
  exit 1
fi

echo "Upstream Debian metadata patch tests passed."
