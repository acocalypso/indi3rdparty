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
  "$fixture/debian/indi-rpi-gpio" \
  "$fixture/debian/indi-avalonud"

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


cat > "$fixture/debian/indi-avalonud/control" <<'EOF'
Package: indi-avalonud
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: Avalon Unified runtime

Package: indi-avalonud-dbg
Depends: indi-avalon (= ${binary:Version}), ${misc:Depends}
Description: Avalon Unified debug package
EOF

for control in indi-asi-power indi-rpi-gpio; do
  cat > "$fixture/debian/$control/control" <<'EOF'
Package: test-pigpio
Depends: ${shlibs:Depends}, ${misc:Depends}, libpigpiod-if2-1, libpigpiod
Description: pigpio test package
EOF
done

mkdir -p "$fixture/debian/libfishcamp" "$fixture/debian/indi-atik-efw"
printf '%s\n' 'lib/firmware/gdr_usb.hex' 'usr/lib/*/libfishcamp.so.1' > "$fixture/debian/libfishcamp/libfishcamp.install"
printf '%s\n' '#!/usr/bin/make -f' > "$fixture/debian/indi-atik-efw/rules"
chmod 0644 "$fixture/debian/indi-atik-efw/rules"

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

if ! grep -Fq 'Depends: indi-avalonud (= ${binary:Version}), ${misc:Depends}' \
  "$fixture/debian/indi-avalonud/control"; then
  echo "indi-avalonud debug dependency was not corrected" >&2
  exit 1
fi

[[ -x "$fixture/debian/indi-atik-efw/rules" ]] || {
  echo "Upstream Debian rules remain non-executable" >&2
  exit 1
}
grep -Fxq 'usr/lib/firmware/gdr_usb.hex' "$fixture/debian/libfishcamp/libfishcamp.install"
grep -Fxq 'usr/lib/*/libfishcamp.so.1' "$fixture/debian/libfishcamp/libfishcamp.install"

echo "Upstream Debian metadata patch tests passed."
