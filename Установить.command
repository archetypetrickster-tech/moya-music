#!/bin/zsh
set -euo pipefail
cd -- "$(dirname "$0")"
finish() {
    local result_code=$?
    if (( result_code )); then
        print -- ''
        print -- 'Действие не завершено. Причина указана выше; исправьте её и запустите этот файл ещё раз.'
    fi
    if [[ -t 0 ]]; then
        print -- 'Нажмите Enter, чтобы закрыть это окно.'
        read -r || true
    fi
    return "$result_code"
}
trap finish EXIT
typeset -a install_flags
install_flags=()
if [[ "${1:-}" == '--configure-only' ]]; then
    install_flags+=(--configure-only)
    print -- 'Моя музыка — настройка автозапуска'
else
    print -- 'Моя музыка — установка / обновление'
fi
print -- '1 — Без автозапуска'
print -- '2 — Запуск при входе в систему'
print -- '3 — Запуск при входе и при подключении наушников'
print -- 'При обновлении выберите нужный режим заново.'
print -n -- 'Выбор [1]: '
read -r choice || choice=1
case "${choice:-1}" in
    1) ;;
    2) install_flags+=(--login) ;;
    3) install_flags+=(--login --headphones) ;;
    *) print -- 'Неверный выбор. Установка отменена.'; exit 1 ;;
esac
result_code=0
zsh Исходники/install.sh "${install_flags[@]}" || result_code=$?
if (( result_code == 73 )); then
    print -- ''
    print -- 'Скопируйте «Моя музыка.app» из открывшейся папки в Программы через Finder.'
    print -- 'При обновлении выберите «Заменить» и подтвердите запрос macOS, если он появится.'
    /usr/bin/open -R "$PWD/Моя музыка.app" || true
    /usr/bin/open /Applications || true
    print -n -- 'Когда копирование закончится, нажмите Enter (или Ctrl+C для отмены): '
    read -r
    zsh Исходники/install.sh --configure-only "${install_flags[@]}"
else
    exit "$result_code"
fi
