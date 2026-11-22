#!/bin/bash
# Check the built packages before they are released, one check per call so a
# failing step names itself in the workflow:
#
#   audit.sh control       the control fields the OwnGoal source requires, and
#                          the identity and firmware floor from apelin-project.json
#   audit.sh ownership     every file in the package is root's
#   audit.sh slices        the dylib carries exactly its package architecture's slices
#   audit.sh signature     the dylib is ad hoc signed
#   audit.sh entitlements  the dylib carries no entitlements
#   audit.sh filter        the filter plist names the executables of the project
set -eu

cd "$(dirname "$0")/../.."
project=apelin-project.json
check="${1:?usage: audit.sh control|ownership|slices|signature|entitlements|filter}"

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

# Extract one package without running any maintainer script; the caller removes it.
extract() {
  dir="$(mktemp -d "${TMPDIR:-/tmp}/devicehubenabler-audit.XXXXXX")"
  dpkg-deb -x "$1" "$dir"
}

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
    slices)
      extract "$deb"
      dylib="$dir/Library/MobileSubstrate/DynamicLibraries/$product.dylib"
      [ -x "$dylib" ] || fail "$deb: $product.dylib missing or not executable"
      got="$(lipo -archs "$dylib")"
      echo "$deb: $product.dylib slices: $got (expected $expected)"
      [ "$got" = "$expected" ] || fail "$deb: slices $got, expected $expected"
      rm -rf "$dir"
      ;;
    signature)
      extract "$deb"
      dylib="$dir/Library/MobileSubstrate/DynamicLibraries/$product.dylib"
      echo "ldid -v: $(ldid -v 2>&1 | head -n1)"
      echo "codesign -dvv:"
      codesign -dvv "$dylib" 2>&1 || echo "codesign -dvv exit $?"
      echo "codesign -v:"
      codesign -v "$dylib" 2>&1 || echo "codesign -v exit $?"
      codesign -dvv "$dylib" 2>&1 | grep -Eq 'Signature=adhoc|flags=0x[0-9a-f]*\((.*)?adhoc' \
        || fail "$deb: $product.dylib is not ad hoc signed"
      rm -rf "$dir"
      ;;
    entitlements)
      extract "$deb"
      dylib="$dir/Library/MobileSubstrate/DynamicLibraries/$product.dylib"
      entitlements="$(ldid -e "$dylib" 2>/dev/null || true)"
      echo "$deb: entitlements: ${entitlements:-<none>}"
      [ -z "$(printf '%s' "$entitlements" | grep '<key>')" ] \
        || fail "$deb: $product.dylib carries entitlements"
      rm -rf "$dir"
      ;;
    filter)
      extract "$deb"
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
