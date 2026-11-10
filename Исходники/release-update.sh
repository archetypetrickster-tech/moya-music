#!/bin/zsh
# Prepare signed updater assets. Does not publish anything.
set -eu
cd "$(dirname "$0")"
if [[ $# != 2 ]]; then
    print -u2 -- 'Использование: zsh release-update.sh /путь/Моя\ музыка.app /путь/к/новой/папке'
    exit 1
fi
app="$(cd "$1" && pwd)"
release_dir="$2"
mkdir -p "$release_dir"
release_dir="$(cd "$release_dir" && pwd)"
build_work="$(mktemp -d "${TMPDIR:-/tmp}/moyamusic-release.XXXXXX")"
trap 'rm -rf "$build_work"' EXIT
source ./sparkle.sh
prepare_sparkle "$build_work/sparkle"
account="ru.ninesquares.moyamusic"
plist="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")"
public_key="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$plist")"
if [[ "$("$build_work/sparkle/bin/generate_keys" --account "$account" -p)" != "$public_key" ]]; then
    print -u2 -- 'Ключ в Связке ключей не совпадает с публичным ключом приложения. Выпуск остановлен.'
    exit 1
fi
codesign --verify --deep --strict "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$release_dir/my-music-update.zip"
"$build_work/sparkle/bin/generate_appcast" --account "$account" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/archetypetrickster-tech/my-music/releases/download/v$version/" \
    --link 'https://github.com/archetypetrickster-tech/my-music' "$release_dir"
"$build_work/sparkle/bin/sign_update" --account "$account" --verify "$release_dir/appcast.xml"
print -- "Подписанные файлы подготовлены: $release_dir"
