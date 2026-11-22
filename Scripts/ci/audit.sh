#!/bin/bash
# Check the built packages before they are released: the control fields the
# OwnGoal source requires, the identity from apelin-project.json, the dylib's
# slices and ad hoc signature, the filter, and root ownership of every file.
set -eu

cd "$(dirname "$0")/../.."
project=apelin-project.json
product="$(jq -r --arg id "$(jq -r .package.tweakFilter.dylib "$project")" \
  '.products[] | select(.id == $id) | .name' "$project")"

shopt -s nullglob
debs=(build/*.deb)
if [ "${#debs[@]}" -ne 2 ]; then
  echo "expected two packages in build/, found ${#debs[@]}" >&2
  exit 1
fi

for deb in "${debs[@]}"; do
  arch="$(dpkg-deb -f "$deb" Architecture)"
  case "$arch" in
    iphoneos-arm64e) expected="arm64e" ;;
    iphoneos-arm64) expected="arm64 arm64e" ;;
    *) echo "$deb: unexpected Architecture $arch" >&2; exit 1 ;;
  esac
  for field in Package Name Version Architecture Description Maintainer Author Section Depends; do
    [ -n "$(dpkg-deb -f "$deb" "$field")" ] || { echo "$deb: control lacks $field" >&2; exit 1; }
  done
  [ "$(dpkg-deb -f "$deb" Package)" = "$(jq -r .package.id "$project")" ] || { echo "$deb: wrong Package" >&2; exit 1; }
  [ "$(dpkg-deb -f "$deb" Version)" = "$(jq -r .package.version "$project")" ] || { echo "$deb: wrong Version" >&2; exit 1; }
  dpkg-deb -f "$deb" Depends | grep -Eq "(^|, )firmware \(>= $(jq -r .deploymentTarget "$project")\)(,|$)" \
    || { echo "$deb: Depends lacks the firmware floor" >&2; exit 1; }

  # Every file is root's: the installer does not chown for a package.
  if dpkg-deb -c "$deb" | awk '{ print $2 }' | grep -qv '^root/root$'; then
    echo "$deb: a file is not owned by root/root" >&2
    exit 1
  fi

  # Extraction only: no maintainer script runs here.
  dir="$(mktemp -d "${TMPDIR:-/tmp}/devicehubenabler-audit.XXXXXX")"
  dpkg-deb -x "$deb" "$dir"
  dylib="$dir/Library/MobileSubstrate/DynamicLibraries/$product.dylib"
  plist="$dir/Library/MobileSubstrate/DynamicLibraries/$product.plist"
  [ -x "$dylib" ] || { echo "$deb: $product.dylib missing or not executable" >&2; exit 1; }
  got="$(lipo -archs "$dylib")"
  [ "$got" = "$expected" ] || { echo "$deb: slices $got, expected $expected" >&2; exit 1; }
  codesign -dv "$dylib" 2>&1 | grep -q 'Signature=adhoc' \
    || { echo "$deb: $product.dylib is not ad hoc signed" >&2; exit 1; }
  [ -z "$(ldid -e "$dylib")" ] || { echo "$deb: $product.dylib carries entitlements" >&2; exit 1; }
  grep -q '<string>dtremotedisplayd</string>' "$plist" \
    || { echo "$deb: the filter does not name dtremotedisplayd" >&2; exit 1; }
  rm -rf "$dir"
  echo "$deb: ok ($arch, slices $got)"
done
