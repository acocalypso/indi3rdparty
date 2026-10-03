#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"
cat > "$fixture/bin/dpkg" <<'EOF'
#!/usr/bin/env bash
echo arm64
EOF
cat > "$fixture/bin/dpkg-scanpackages" <<'EOF'
#!/usr/bin/env bash
echo 'Package: fixture'
EOF
cat > "$fixture/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
if [[ "$TEST_CASE" == install-failure && "$*" == *libmeadecam* ]]; then exit 1; fi
if [[ "$*" == *libmeadecam* ]]; then
  [[ -f "$TEST_ROOT/all_debs/libtoupcam_1_arm64.deb" ]] || exit 1
fi
EOF
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
for test_case in success build-failure no-debs install-failure; do
  root="$fixture/$test_case"
  mkdir -p "$root"
  for target in libtoupcam libmeadecam libricohcamerasdk indi-test; do
    mkdir -p "$root/$target" "$root/debian/$target"
    touch "$root/debian/$target/rules"
  done
  cat > "$root/make_deb_pkgs" <<'EOF'
#!/usr/bin/env bash
set -eu
if [[ "$1" == libricohcamerasdk ]]; then exit 99; fi
if [[ "$1" == libmeadecam ]]; then
  case "$TEST_CASE" in
    build-failure) touch partial_1_arm64.deb; exit 1 ;;
    no-debs) exit 0 ;;
  esac
fi
touch "${1}_1_arm64.deb"
EOF
  export TEST_CASE="$test_case" TEST_ROOT="$root"
  export GITHUB_STEP_SUMMARY="$root/summary"
  # Windows working copies may contain CRLF; execute the repository content
  # using the LF line endings used by Actions checkouts.
  tr -d '\r' < "$script_dir/../../build_debs.sh" > "$root/build_debs.sh"
  if (cd "$root" && bash build_debs.sh > log 2>&1); then
    [[ "$test_case" == success ]] || { cat "$root/log"; exit 1; }
    [[ -f "$root/dist/indi-test_1_arm64.deb" ]]
  else
    [[ "$test_case" != success ]] || { cat "$root/log"; exit 1; }
    [[ ! -f "$root/dist/indi-test_1_arm64.deb" ]]
    grep -q 'Failed targets:.*libmeadecam' "$root/build-report.txt"
  fi
  grep -q 'libricohcamerasdk(no-arm64-sdk)' "$root/build-report.txt"
  grep -q 'indi-test' "$root/summary"
  if [[ "$test_case" == build-failure ]]; then
    [[ -f "$root/failed_debs/libmeadecam/partial_1_arm64.deb" ]]
    [[ ! -f "$root/all_debs/partial_1_arm64.deb" ]]
  fi
done
echo "Package build failure and dependency-order tests passed."
