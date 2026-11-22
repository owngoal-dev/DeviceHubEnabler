#!/bin/bash
# Build the DeviceHubEnabler packages without Apelin, for GitHub Actions: one
# .deb per bootstrap from Sources/*.m and apelin-project.json, built the way
# Apelin builds them on a device (same flags, same substrate stubs, same
# layout). apelin-project.json stays the single source of the package's
# identity: version, description, author, dependencies, filter and scripts.
#
#   Scripts/ci/build.sh                    both packages land in build/
#   DHE_SKIP_DEB=1 Scripts/ci/build.sh     stage the package trees only, no dpkg-deb
#
# Needs clang with the iPhoneOS SDK (SDKROOT, or `xcrun --sdk iphoneos`), jq,
# lipo, strip, ldid and, unless DHE_SKIP_DEB is set, dpkg-deb. Written for the
# macOS runner's bash 3.2.
set -eu

cd "$(dirname "$0")/../.."
project=apelin-project.json
ci=Scripts/ci
out=build

package_id="$(jq -r .package.id "$project")"
version="$(jq -r .package.version "$project")"
package_name="$(jq -r .package.name "$project")"
description="$(jq -r .package.description "$project")"
author="$(jq -r .package.author "$project")"
section="$(jq -r .package.section "$project")"
icon="$(jq -r '.package.icon // ""' "$project")"
depends="$(jq -r '.package.depends // [] | join(", ")' "$project")"
deployment_target="$(jq -r .deploymentTarget "$project")"
postinst="$(jq -r '.package.maintainerScripts.postinst // ""' "$project")"
product="$(jq -r --arg id "$(jq -r .package.tweakFilter.dylib "$project")" \
  '.products[] | select(.id == $id) | .name' "$project")"
executables="$(jq -r '.package.tweakFilter.executables | join("\n")' "$project")"

build_id="ci-${GITHUB_SHA:-local}"
build_id="${build_id:0:14}"

sdk="${SDKROOT:-$(xcrun --sdk iphoneos --show-sdk-path)}"
common=(-isysroot "$sdk" "-mios-version-min=$deployment_target" -O2 -Wall -Wextra
  -Werror=unguarded-availability-new -fvisibility=hidden -fobjc-arc
  "-DAPELIN_BUILD_ID=\"$build_id\"" "-DAPELIN_PACKAGE_ID=\"$package_id\""
  "-DAPELIN_VERSION=\"$version\"" "-DAPELIN_PRODUCT_NAME=\"$product\""
  -DAPELIN_CONFIGURATION_RELEASE=1)

rm -rf "$out"
mkdir -p "$out"

for bootstrap in roothide rootless; do
  # Package architecture, the substrate stub naming where that bootstrap's
  # mobilesubstrate lives, the rpaths it needs, and what @PREFIX@/@ROOTFS@ become.
  case "$bootstrap" in
    roothide)
      package_arch=iphoneos-arm64e; stub="$ci/lib/roothide"; prefix=""; rootfs=/rootfs; rpaths="" ;;
    rootless)
      package_arch=iphoneos-arm64; stub="$ci/lib/rootless"; prefix=/var/jb; rootfs=""
      rpaths="-Wl,-rpath,/var/jb/Library/Frameworks -Wl,-rpath,/var/jb/usr/lib" ;;
    *) echo "unknown bootstrap $bootstrap" >&2; exit 2 ;;
  esac
  upper="$(printf '%s' "$bootstrap" | tr '[:lower:]' '[:upper:]')"
  archs="$(jq -r --arg b "$bootstrap" '.architectures[$b] | join(" ")' "$project")"

  work="$(mktemp -d "${TMPDIR:-/tmp}/devicehubenabler.XXXXXX")"
  dylib="$work/$product.dylib"
  slices=()
  for arch in $archs; do
    objects=()
    for source in Sources/*.m; do
      obj="$work/$arch-$(basename "$source" .m).o"
      clang -arch "$arch" "${common[@]}" "-DAPELIN_BOOTSTRAP_$upper=1" \
        -I"$ci/include" -c "$source" -o "$obj"
      objects+=("$obj")
    done
    clang -arch "$arch" -isysroot "$sdk" "-mios-version-min=$deployment_target" \
      -dynamiclib -install_name "@rpath/$product.dylib" -fobjc-arc \
      -L"$stub" $rpaths -framework Foundation -lsubstrate "${objects[@]}" -o "$work/$arch.dylib"
    slices+=("$work/$arch.dylib")
  done
  if [ "${#slices[@]}" -eq 1 ]; then
    cp "${slices[0]}" "$dylib"
  else
    lipo -create "${slices[@]}" -output "$dylib"
  fi
  strip -x "$dylib"
  ldid -S "$dylib"

  # The package tree as the installer sees it: the dylib and its filter under
  # /Library/MobileSubstrate/DynamicLibraries, the control and maintainer scripts.
  tree="$work/tree"
  dynamic="$tree/Library/MobileSubstrate/DynamicLibraries"
  mkdir -p "$tree/DEBIAN" "$dynamic"
  cp "$dylib" "$dynamic/$product.dylib"
  chmod 0755 "$dynamic/$product.dylib"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict><key>Filter</key><dict><key>Executables</key><array>'
    printf '%s\n' "$executables" | while IFS= read -r executable; do
      printf '<string>%s</string>\n' "$executable"
    done
    echo '</array></dict></dict></plist>'
  } >"$dynamic/$product.plist"
  chmod 0644 "$dynamic/$product.plist"
  if [ -n "$postinst" ]; then
    sed -e "s|@PREFIX@|$prefix|g" -e "s|@ROOTFS@|$rootfs|g" "$postinst" >"$tree/DEBIAN/postinst"
    chmod 0755 "$tree/DEBIAN/postinst"
  fi
  {
    echo "Package: $package_id"
    echo "Name: $package_name"
    echo "Version: $version"
    echo "Architecture: $package_arch"
    echo "Description: $description"
    echo "Maintainer: $author"
    echo "Author: $author"
    echo "Section: $section"
    echo "Depends: firmware (>= $deployment_target), $depends"
    if [ -n "$icon" ]; then
      echo "Icon: $icon"
    fi
  } >"$tree/DEBIAN/control"

  if [ "${DHE_SKIP_DEB:-0}" = 1 ]; then
    mkdir -p "$out/$bootstrap"
    cp -R "$tree" "$out/$bootstrap/tree"
    echo "staged $bootstrap under $out/$bootstrap/tree"
  else
    deb="$out/${package_id}_${version}_${package_arch}.deb"
    dpkg-deb --root-owner-group -b "$tree" "$deb"
    echo "built $deb"
  fi
done
