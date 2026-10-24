#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="ChargeCap.app"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/chargecap-build.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
if [ ! -f artwork/ChargeCap.icns ] || [ artwork/draw-icon.m -nt artwork/ChargeCap.icns ] || [ build.sh -nt artwork/ChargeCap.icns ]; then
  xcrun clang -fobjc-arc -Os -Wall -Wextra -Werror -framework AppKit artwork/draw-icon.m -o "$temporary/icon"
  "$temporary/icon" "$temporary/png"
  mkdir "$temporary/ChargeCap.iconset"
  for size in 16 32; do
    cp "$temporary/png/chargecap-$size.png" "$temporary/ChargeCap.iconset/icon_${size}x${size}.png"
    double=$((size * 2))
    cp "$temporary/png/chargecap-$double.png" "$temporary/ChargeCap.iconset/icon_${size}x${size}@2x.png"
  done
  cp "$temporary/png/chargecap-128.png" "$temporary/ChargeCap.iconset/icon_128x128.png"
  iconutil -c icns "$temporary/ChargeCap.iconset" -o artwork/ChargeCap.icns
fi
xcrun clang -arch arm64 -fobjc-arc -Os -DNDEBUG -Wall -Wextra -Werror \
  -mmacosx-version-min=26.4 -framework AppKit -framework QuartzCore -framework IOSurface \
  src/main.m -Wl,-dead_strip -o "$temporary/ChargeCap"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
mv "$temporary/ChargeCap" "$app/Contents/MacOS/ChargeCap"
cp Info.plist "$app/Contents/Info.plist"
cp artwork/ChargeCap.icns "$app/Contents/Resources/ChargeCap.icns"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf 'Built %s/%s\n' "$PWD" "$app"
