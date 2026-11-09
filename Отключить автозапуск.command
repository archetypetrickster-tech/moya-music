#!/bin/zsh
set -euo pipefail
cd -- "$(dirname "$0")"
finish() {
    local result_code=$?
    if (( result_code )); then print -- 'Не удалось отключить автозапуск. Причина указана выше.'; fi
    if [[ -t 0 ]]; then
        print -- 'Нажмите Enter, чтобы закрыть это окно.'
        read -r || true
    fi
    return "$result_code"
}
trap finish EXIT
/bin/zsh Исходники/install.sh --disable-autostart
