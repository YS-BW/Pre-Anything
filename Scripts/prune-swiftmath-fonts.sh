#!/bin/sh

set -eu

font_directory="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/SwiftMath_SwiftMath.bundle/Contents/Resources/mathFonts.bundle"

if [ ! -d "${font_directory}" ]; then
    exit 0
fi

# Pre-Anything always uses MTFontManager.defaultFont, which is Latin Modern Math.
# Keep that font, its metrics, and all upstream license files; remove alternate
# families and the upstream conversion utility from this target's build product.
find "${font_directory}" -maxdepth 1 -type f \( -name '*.otf' -o -name '*.plist' \) \
    ! -name 'latinmodern-math.otf' \
    ! -name 'latinmodern-math.plist' \
    -delete

conversion_utility="${font_directory}/math_table_to_plist.py"
if [ -f "${conversion_utility}" ]; then
    rm "${conversion_utility}"
fi
