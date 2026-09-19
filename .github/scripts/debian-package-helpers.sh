#!/usr/bin/env bash

# Helpers for validating and completing hand-built Debian packages.
# Callers are expected to enable `set -euo pipefail`.

debian_merge_depends() {
  local lists=("$@")
  local item key
  local -A seen=()
  local -a merged=()

  for list in "${lists[@]}"; do
    while IFS= read -r item; do
      item="$(printf '%s' "$item" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      [[ -n "$item" ]] || continue

      # Retain the first relationship for a package. Generated, versioned
      # relationships are passed before any existing weaker relationships.
      key="$(printf '%s' "$item" | sed -E 's/[[:space:]]*\(.*$//; s/[[:space:]]*\|.*$//')"
      if [[ -z "${seen[$key]:-}" ]]; then
        seen[$key]=1
        merged+=("$item")
      fi
    done < <(printf '%s\n' "$list" | tr ',' '\n')
  done

  local IFS=', '
  printf '%s' "${merged[*]}"
}

debian_collect_elf_files() {
  local root="$1"
  local file

  while IFS= read -r -d '' file; do
    if readelf -h "$file" >/dev/null 2>&1; then
      printf '%s\0' "$file"
    fi
  done < <(find "$root" -type f -print0)
}

debian_collect_elf_directories() {
  local root="$1"
  local file directory
  local -A seen=()

  while IFS= read -r -d '' file; do
    directory="$(dirname "$file")"
    if [[ -z "${seen[$directory]:-}" ]]; then
      seen[$directory]=1
      printf '%s\0' "$directory"
    fi
  done < <(debian_collect_elf_files "$root")
}

debian_write_private_shlibs() {
  local output_file="$1"
  local provider="$2"
  local root="$3"
  local file soname library abi

  while IFS= read -r -d '' file; do
    soname="$(readelf -d "$file" 2>/dev/null | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p' | head -n 1)"
    [[ -n "$soname" ]] || continue

    if [[ "$soname" =~ ^(lib.+)\.so\.([0-9]+)($|\.) ]]; then
      library="${BASH_REMATCH[1]}"
      abi="${BASH_REMATCH[2]}"
      printf '%s %s %s\n' "$library" "$abi" "$provider" >> "$output_file"
    fi
  done < <(debian_collect_elf_files "$root")
}

# Print the comma-separated dependency list produced by dpkg-shlibdeps.
# Extra provider specifications use ROOT|DEBIAN_RELATIONSHIP, for example:
#   /tmp/indi-core-stage|libindi1
debian_generate_shlib_depends() {
  local package_name="$1"
  local package_root="$2"
  shift 2

  [[ -d "$package_root" ]] || {
    echo "Package root does not exist: $package_root" >&2
    return 1
  }
  package_root="$(readlink -f "$package_root")"

  local -a elf_files=()
  mapfile -d '' -t elf_files < <(debian_collect_elf_files "$package_root")
  if (( ${#elf_files[@]} == 0 )); then
    return 0
  fi

  local work_dir
  work_dir="$(mktemp -d)"
  mkdir -p "$work_dir/debian"
  cat > "$work_dir/debian/control" <<EOF
Source: indi3rdparty-dependency-scan
Section: misc
Priority: optional
Maintainer: INDI 3rdparty CI <noreply@github.com>
Standards-Version: 4.7.0

Package: $package_name
Architecture: any
Description: Temporary package metadata for dependency generation
EOF

  local shlibs_file="$work_dir/debian/shlibs.local"
  : > "$shlibs_file"
  debian_write_private_shlibs "$shlibs_file" "$package_name" "$package_root"

  local -a library_roots=("$package_root")
  local spec root provider
  for spec in "$@"; do
    root="${spec%%|*}"
    provider="${spec#*|}"
    [[ -d "$root" ]] || {
      echo "Private library root does not exist: $root" >&2
      rm -rf "$work_dir"
      return 1
    }
    root="$(readlink -f "$root")"
    library_roots+=("$root")
    debian_write_private_shlibs "$shlibs_file" "$provider" "$root"
  done
  sort -u -o "$shlibs_file" "$shlibs_file"

  local -a args=(-O "-x$package_name")
  local library_root library_dir
  for library_root in "${library_roots[@]}"; do
    while IFS= read -r -d '' library_dir; do
      args+=("-l$library_dir")
    done < <(debian_collect_elf_directories "$library_root")
  done

  local elf
  for elf in "${elf_files[@]}"; do
    args+=("-e$elf")
  done

  local output
  if ! output="$(cd "$work_dir" && dpkg-shlibdeps "${args[@]}")"; then
    rm -rf "$work_dir"
    return 1
  fi
  rm -rf "$work_dir"

  printf '%s\n' "$output" | sed -n 's/^shlibs:Depends=//p'
}

debian_control_set_depends() {
  local control_file="$1"
  local depends="$2"
  local temporary

  [[ -f "$control_file" ]] || {
    echo "Debian control file not found: $control_file" >&2
    return 1
  }
  [[ -n "$depends" ]] || return 0

  temporary="$(mktemp)"
  awk -v depends="$depends" '
    BEGIN { written = 0 }
    /^Depends:/ {
      if (!written) {
        print "Depends: " depends
        written = 1
      }
      next
    }
    /^Description:/ && !written {
      print "Depends: " depends
      written = 1
    }
    { print }
    END {
      if (!written) print "Depends: " depends
    }
  ' "$control_file" > "$temporary"
  mv "$temporary" "$control_file"
}

debian_validate_package() {
  local deb_path="$1"
  local package_name version architecture root_mode

  package_name="$(dpkg-deb -f "$deb_path" Package)"
  version="$(dpkg-deb -f "$deb_path" Version)"
  architecture="$(dpkg-deb -f "$deb_path" Architecture)"

  [[ -n "$package_name" && -n "$version" && -n "$architecture" ]] || {
    echo "Required control metadata is missing from $deb_path" >&2
    return 1
  }

  root_mode="$(dpkg-deb --fsys-tarfile "$deb_path" | tar -tvf - | awk '$NF == "./" { print substr($1, 1, 10); exit }')"
  if [[ "$root_mode" != 'drwxr-xr-x' ]]; then
    echo "$package_name has unsafe archive root permissions: ${root_mode:-missing}" >&2
    return 1
  fi

  echo "Validated $package_name $version ($architecture); Depends: $(dpkg-deb -f "$deb_path" Depends 2>/dev/null || echo '<none>')"
}

debian_assert_elf_closure() {
  local -a inputs=("$@")
  local extract_root
  extract_root="$(mktemp -d)"

  local -a library_roots=("$extract_root")
  local input
  for input in "${inputs[@]}"; do
    if [[ -d "$input" ]]; then
      library_roots+=("$(readlink -f "$input")")
    else
      dpkg-deb -x "$input" "$extract_root"
    fi
  done

  local -a library_dirs=()
  local library_root library_dir
  for library_root in "${library_roots[@]}"; do
    while IFS= read -r -d '' library_dir; do
      library_dirs+=("$library_dir")
    done < <(debian_collect_elf_directories "$library_root")
  done
  local library_path
  library_path="$(IFS=:; printf '%s' "${library_dirs[*]}")"

  local file ldd_output failed=0
  while IFS= read -r -d '' file; do
    ldd_output="$(LD_LIBRARY_PATH="$library_path" ldd "$file" 2>&1 || true)"
    if printf '%s\n' "$ldd_output" | grep -q 'not found'; then
      echo "Unresolved shared-library dependency in $file:" >&2
      printf '%s\n' "$ldd_output" >&2
      failed=1
    fi
  done < <(debian_collect_elf_files "$extract_root")

  rm -rf "$extract_root"
  [[ "$failed" -eq 0 ]]
}
