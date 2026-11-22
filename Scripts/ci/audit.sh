#!/bin/bash
# Check the built packages before they are released, one check per call so a
# failing step names itself in the workflow:
#
#   audit.sh control     the control fields the OwnGoal source requires, and the
#                        identity and firmware floor from apelin-project.json
#   audit.sh ownership   every file in the package is root's
#   audit.sh binary      the dylib's slices for its package architecture, an ad
#                        hoc signature and no entitlements
#   audit.sh filter      the filter plist names the executables of the project
set -eu

cd "$(dirname "$0")/../.."
project=apelin-project.json
check="${1:?usage: audit.sh control|ownership|binary|filter}"

product="$(jq -r --arg id "$(jq -r .package.tweakFilter.dylib "$project")" \
  '.products[] | select(.id == $id) | .name' "$project")"
executables="$(jq -r '.package.tweakFilter.executables[]' "$project")"

shopt -s nullglob
debs=(build/*.deb)
if [ "${#debs[@]}" -ne 2 ]; then
  echo "expected two packages in build/, found ${#debs[@]}" >&2
  exit 1
fi

fail() { echo "$1" >&2; exit 1; }

for deb in "${debs[@]}"; do
  arch="$(dpkg-deb -f "$deb" Architecture)"
  case "$arch" in
    iphoneos-arm64e) expected="arm64e" ;;
    iphoneos-arm64) expected="arm64 arm64e" ;;
    *) fail "$deb: unexpected Architecture $arch" ;;
  esac

  case "$check" in
    control)
      echo "== $deb"
      for field in Package Name Version Architecture Description Maintainer Author Section Depends; do
        value="$(dpkg-deb -f "$deb" "$field")"
        [ -n "$value" ] || fail "$deb: control lacks $field"
        printf '%s: %s\n' "$field" "$value"
      done
      [ "$(dpkg-deb -f "$deb" Package)" = "$(jq -r .package.id "$project")" ] || fail "$deb: wrong Package"
      [ "$(dpkg-deb -f "$deb" Version)" = "$(jq -r .package.version "$project")" ] || fail "$deb: wrong Version"
      dpkg-deb -f "$deb" Depends | grep -Eq "(^|, )firmware \(>= $(jq -r .deploymentTarget "$project")\)(,|$)" \
        || fail "$deb: Depends lacks the firmware floor"
      ;;
    ownership)
      echo "== $deb"
      dpkg-deb -c "$deb"
      # The installer does not chown for a package: every entry must be root's.
      if dpkg-deb -c "$deb" | awk '{ print $2 }' | grep -qv '^root/root$'; then
        fail "$deb: a file is not owned by root/root"
      fi
      ;;
    binary)
      # Extraction only: no maintainer script runs here.
      dir="$(mktemp -d "${TMPDIR:-/tmp}/devicehubenabler-audit.XXXXXX")"
      dpkg-deb -x "$deb" "$dir"
      dylib="$dir/Library/MobileSubstrate/DynamicLibraries/$product.dylib"
      [ -x "$dylib" ] || fail "$deb: $product.dylib missing or not executable"
      got="$(lipo -archs "$dylib")"
      [ "$got" = "$expected" ] || fail "$deb: slices $got, expected $expected"
      codesign -dv "$dylib" 2>&1 || true
      codesign -dv "$dylib" 2>&1 | grep -q 'Signature=adhoc' \
        || fail "$deb: $product.dylib is not ad hoc signed"
      entitlements="$(ldid -e "$dylib" | tr -d '[:space:]')"
      [ -z "$entitlements" ] || fail "$deb: $product.dylib carries entitlements"
      rm -rf "$dir"
      echo "$deb: $product.dylib has slices $got, ad hoc signed, no entitlements"
      ;;
    filter)
      dir="$(mktemp -d "${TMPDIR:-/tmp}/devicehubenabler-audit.XXXXXX")"
      dpkg-deb -x "$deb" "$dir"
      plist="$dir/Library/MobileSubstrate/DynamicLibraries/$product.plist"
      cat "$plist"
      for executable in $executables; do
        grep -q "<string>$executable</string>" "$plist" \
          || fail "$deb: the filter does not name $executable"
      done
      rm -rf "$dir"
      ;;
    *) fail "unknown check $check" ;;
  esac
done
