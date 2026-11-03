#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(defaults read /Applications/Lexique.app/Contents/Info.plist CFBundleShortVersionString)
STAGE=$(mktemp -d)
cp -R /Applications/Lexique.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<TXT
Lexique $VERSION

Drag Lexique to the Applications folder.

Lexique is ad-hoc signed and not notarized. If macOS blocks the first launch:
right-click the app, choose Open, then Open again. Or run:

    xattr -dr com.apple.quarantine /Applications/Lexique.app

Dictionaries go in:
    ~/Library/Application Support/Lexique/Dictionaries/

Group and order them in order.txt in the same folder. No dictionaries are bundled.
TXT

mkdir -p dist
rm -f "dist/Lexique-$VERSION.dmg"
hdiutil create -volname "Lexique" -srcfolder "$STAGE" -ov -format UDZO "dist/Lexique-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
echo "dist/Lexique-$VERSION.dmg"
