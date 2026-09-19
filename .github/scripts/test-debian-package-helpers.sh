#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=debian-package-helpers.sh
source "$script_dir/debian-package-helpers.sh"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

provider_root="$test_root/provider"
consumer_root="$test_root/consumer"
mkdir -p "$provider_root/usr/lib" "$consumer_root/DEBIAN" "$consumer_root/usr/bin"

cat > "$test_root/provider.c" <<'EOF'
int indi_test_answer(void) { return 42; }
EOF
cat > "$test_root/consumer.c" <<'EOF'
extern int indi_test_answer(void);
int main(void) { return indi_test_answer() == 42 ? 0 : 1; }
EOF

gcc -fPIC -shared -Wl,-soname,libindi-test.so.1 \
  -o "$provider_root/usr/lib/libindi-test.so.1.0" "$test_root/provider.c"
ln -s libindi-test.so.1.0 "$provider_root/usr/lib/libindi-test.so.1"
ln -s libindi-test.so.1 "$provider_root/usr/lib/libindi-test.so"
gcc -o "$consumer_root/usr/bin/indi-test" "$test_root/consumer.c" \
  -L"$provider_root/usr/lib" -lindi-test

generated="$(debian_generate_shlib_depends \
  indi-test-driver \
  "$consumer_root" \
  "$provider_root|libindi1")"

[[ "$generated" == *libindi1* ]] || {
  echo "Expected generated Depends to contain libindi1; got: $generated" >&2
  exit 1
}
[[ "$generated" == *libc6* ]] || {
  echo "Expected generated Depends to contain libc6; got: $generated" >&2
  exit 1
}

merged="$(debian_merge_depends "$generated" 'ca-certificates, libc6')"
[[ "$merged" == *ca-certificates* ]] || {
  echo "Dependency merge lost an existing non-ELF dependency: $merged" >&2
  exit 1
}

cat > "$consumer_root/DEBIAN/control" <<EOF
Package: indi-test-driver
Version: 1.0
Architecture: $(dpkg --print-architecture)
Maintainer: INDI 3rdparty CI <noreply@github.com>
Depends: $merged
Description: Dependency generation test package
EOF

package_path="$test_root/indi-test-driver.deb"
dpkg-deb --root-owner-group --build "$consumer_root" "$package_path" >/dev/null
debian_validate_package "$package_path"
debian_assert_elf_closure "$package_path" "$provider_root"

echo "Debian package helper tests passed."
