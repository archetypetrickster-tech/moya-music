#!/bin/zsh
set -euo pipefail
package_dir="$(cd -- "$(dirname "$0")/.." && pwd)"
source_app="$package_dir/Моя музыка.app"
installed_app='/Applications/Моя музыка.app'
identifier='ru.ninesquares.moyamusic'
login_enabled=0
headphones_enabled=0
configure_only=0
disable_only=0
stage_dir=''
fail() { print -u2 -- "$1"; exit "${2:-1}"; }
cleanup() {
    local result_code=$?
    if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
        if [[ -d "$stage_dir/previous.app" && ! -e "$installed_app" ]]; then
            if ! /bin/mv "$stage_dir/previous.app" "$installed_app"; then
                print -u2 -- "Не удалось вернуть прежнюю версию. Она сохранена: $stage_dir/previous.app"
                return "$result_code"
            fi
        fi
        /bin/rm -rf "$stage_dir"
    fi
    return "$result_code"
}
trap cleanup EXIT
for option in "$@"; do
    case "$option" in
        --login) login_enabled=1 ;;
        --headphones) headphones_enabled=1 ;;
        --configure-only) configure_only=1 ;;
        --disable-autostart) disable_only=1 ;;
        *) fail "Неизвестный параметр: $option" ;;
    esac
done
domain="gui/$(id -u)"
agents="$HOME/Library/LaunchAgents"
support="$HOME/Library/Application Support/MoyaMusic"
logs="$HOME/Library/Logs/MoyaMusic"
disable_autostart() {
    local suffix label
    for suffix in login headphones; do
        label="$identifier.$suffix"
        if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
            /bin/launchctl bootout "$domain/$label"
        fi
        /bin/rm -f "$agents/$label.plist"
    done
}
if (( disable_only )); then
    disable_autostart
    print -- 'Автозапуск при входе и подключении наушников отключён. Приложение и вход в Яндекс сохранены.'
    exit 0
fi
validate_app() {
    local app_path="$1" bundle_identifier
    [[ -d "$app_path" && ! -L "$app_path" ]] || fail 'Не найдено приложение. Полностью распакуйте архив или сначала скопируйте приложение в Программы.'
    bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$bundle_identifier" == "$identifier" ]] || fail 'В папке находится другое приложение «Моя музыка». Оно не изменено.'
    [[ -x "$app_path/Contents/MacOS/MoyaMusic" && -x "$app_path/Contents/Helpers/MoyaMusicHeadphones" ]] || fail 'В приложении отсутствует исполняемый файл. Распакуйте архив заново.'
    /usr/bin/codesign --verify --deep --strict "$app_path" || fail 'Проверка целостности приложения не прошла. Распакуйте исходный архив заново.'
}
if [[ -e "$installed_app" || -L "$installed_app" ]]; then
    [[ ! -L "$installed_app" ]] || fail 'В Программах находится ссылка с таким именем. Установка остановлена.'
    existing_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$existing_identifier" == "$identifier" ]] || fail 'В Программах уже есть другое приложение с таким именем. Оно не изменено.'
fi
if (( configure_only )); then
    validate_app "$installed_app"
else
    validate_app "$source_app"
fi
version_app="$source_app"
if (( configure_only )); then version_app="$installed_app"; fi
minimum_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$version_app/Contents/Info.plist" 2>/dev/null || true)"
# The bundle currently targets macOS 13; compare the declared version before changing anything.
autoload -Uz is-at-least
is-at-least "${minimum_version:-13.0}" "$(/usr/bin/sw_vers -productVersion)" || fail "Для приложения нужна macOS ${minimum_version:-13.0} или новее."
if (( ! configure_only )); then
    [[ -w /Applications ]] || fail 'Для копирования в Программы требуется подтверждение через Finder.' 73
    if [[ -e "$installed_app" && ! -w "$installed_app" ]]; then
        fail 'Для обновления этого приложения требуется подтверждение через Finder.' 73
    fi
    stage_dir="$(/usr/bin/mktemp -d /Applications/.moyamusic-install.XXXXXX)"
    /usr/bin/ditto "$source_app" "$stage_dir/new.app"
    validate_app "$stage_dir/new.app"
    # Wait for the main process before replacing its executable. Startup configuration alone does not stop playback.
    /usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
var apps=$.NSRunningApplication.runningApplicationsWithBundleIdentifier('ru.ninesquares.moyamusic');
var players=[];
for(var i=0;i<apps.count;i++) {
    var app=apps.objectAtIndex(i);
    if(app.executableURL.lastPathComponent.js==='MoyaMusic') { players.push(app); app.terminate; }
}
for(var attempt=0; attempt<80; attempt++) {
    if(players.every(function(app){return Boolean(app.isTerminated);})) break;
    $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
}
if(players.some(function(app){return !Boolean(app.isTerminated);})) throw Error('Закройте «Мою музыку» через ⌘Q и повторите установку.');
JXA
    if [[ -e "$installed_app" ]]; then /bin/mv "$installed_app" "$stage_dir/previous.app"; fi
    /bin/mv "$stage_dir/new.app" "$installed_app"
fi
mkdir -p "$agents" "$support" "$logs"
disable_autostart
xml_text() { print -rn -- "$1" | /usr/bin/sed 's/\&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g;'; }
if (( login_enabled )); then
    login_plist="$agents/$identifier.login.plist"
    cat > "$login_plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>ru.ninesquares.moyamusic.login</string>
<key>AssociatedBundleIdentifiers</key><array><string>ru.ninesquares.moyamusic</string></array>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>/Applications/Моя музыка.app</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST
    /usr/bin/plutil -lint "$login_plist" >/dev/null
    chmod 644 "$login_plist"
    /bin/launchctl bootstrap "$domain" "$login_plist"
fi
if (( headphones_enabled )); then
    helper="$support/MoyaMusicHeadphones"
    /usr/bin/ditto "$installed_app/Contents/Helpers/MoyaMusicHeadphones" "$helper.new"
    /bin/mv -f "$helper.new" "$helper"
    headphones_plist="$agents/$identifier.headphones.plist"
    cat > "$headphones_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>ru.ninesquares.moyamusic.headphones</string>
<key>AssociatedBundleIdentifiers</key><array><string>ru.ninesquares.moyamusic</string></array>
<key>ProgramArguments</key><array><string>$(xml_text "$helper")</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>5</integer><key>ProcessType</key><string>Background</string>
<key>StandardOutPath</key><string>$(xml_text "$logs/headphones.log")</string>
<key>StandardErrorPath</key><string>$(xml_text "$logs/headphones-errors.log")</string>
</dict></plist>
PLIST
    /usr/bin/plutil -lint "$headphones_plist" >/dev/null
    chmod 644 "$headphones_plist"
    /bin/launchctl bootstrap "$domain" "$headphones_plist"
fi
print -- 'Готово. Приложение: Программы → Моя музыка.'
print -- "Запуск при входе: $([[ $login_enabled == 1 ]] && print 'включён' || print 'выключен')."
print -- "Запуск при подключении наушников: $([[ $headphones_enabled == 1 ]] && print 'включён' || print 'выключен')."
/usr/bin/open "$installed_app" || fail 'Приложение установлено, но macOS не разрешила его открыть. Откройте «Мою музыку» из Программ и подтвердите открытие в настройках безопасности.'
