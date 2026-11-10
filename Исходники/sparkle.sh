#!/bin/zsh
# Pinned official distribution. Always verify the cached archive before extraction.
prepare_sparkle() {
    local target="$1"
    local version="2.10.1"
    local expected="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
    local cache="${MOYA_BUILD_CACHE:-$HOME/Library/Caches/MyMusicBuild}"
    local archive="$cache/Sparkle-$version.tar.xz"
    mkdir -p "$cache" "$target"
    if [[ ! -f "$archive" ]] || [[ "$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')" != "$expected" ]]; then
        local download
        download="$(mktemp "$cache/.sparkle.XXXXXX")"
        if ! /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 \
            "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$download"; then
            rm -f "$download"
            return 1
        fi
        if [[ "$(/usr/bin/shasum -a 256 "$download" | /usr/bin/awk '{print $1}')" != "$expected" ]]; then
            rm -f "$download"
            print -u2 -- "Ошибка проверки подлинности загрузки Sparkle. Сборка остановлена."
            return 1
        fi
        mv "$download" "$archive"
    fi
    /usr/bin/tar -xJf "$archive" -C "$target"
}
