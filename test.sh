#!/bin/sh
set -eu
cd "$(dirname "$0")"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/chargecap-tests.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
xcrun clang -fobjc-arc -Os -Wall -Wextra -Werror -framework Foundation src/tests.m -o "$temporary/backend"
"$temporary/backend"
xcrun clang -fobjc-arc -Os -Wall -Wextra -Werror -mmacosx-version-min=26.4 -framework AppKit -framework QuartzCore -framework IOSurface src/ui-tests.m -o "$temporary/slider"
"$temporary/slider"
