"""Checks installation in a temporary folder; never changes the real app or login jobs.
Run on macOS: python3 Исходники/tests/check-installer.py
"""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile

package = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='moyamusic-installer-check-') as temporary:
    root = Path(temporary)
    applications = root / 'Applications'
    applications.mkdir()
    task_home = root / 'Дом & тест'
    mock_bin = root / 'mocks'
    mock_bin.mkdir()
    jobs = root / 'jobs.json'
    quit_marker = root / 'quit-called'
    app = applications / 'Моя музыка.app'
    source_app = package / 'Моя музыка.app'
    original_script = (package / 'Исходники/install.sh').read_text()
    script = root / 'install.sh'

    def mock(name, body):
        path = mock_bin / name
        path.write_text('#!/usr/bin/env python3\n' + body)
        path.chmod(0o755)
        return str(path)

    launchctl = mock('launchctl', f'''import json,sys,plistlib
from pathlib import Path
p=Path({str(jobs)!r}); state=json.loads(p.read_text()) if p.exists() else {{}}
command=sys.argv[1]
if command=='print': sys.exit(0 if sys.argv[2] in state else 1)
if command=='bootout': state.pop(sys.argv[2],None)
if command=='bootstrap':
 with open(sys.argv[3],'rb') as f: value=plistlib.load(f)
 state[sys.argv[2]+'/'+value['Label']]=value
p.write_text(json.dumps(state))
''')
    open_command = mock('open', 'import sys\nsys.exit(0)\n')
    osascript = mock('osascript', f'from pathlib import Path\nPath({str(quit_marker)!r}).touch()\n')
    changed = original_script.replace('/Applications', str(applications)).replace('$HOME/Library', '$task_home/Library')
    changed = changed.replace('/bin/launchctl', launchctl).replace('/usr/bin/open', open_command).replace('/usr/bin/osascript', osascript)
    # Point the script at the unchanged signed package while isolating every installation destination.
    start = changed.index('package_dir=')
    end = changed.index('\nsource_app=', start)
    changed = changed[:start] + 'package_dir=' + "'" + str(package).replace("'", "'\\''") + "'" + changed[end:]
    changed = changed.replace('source_app=', 'task_home=' + "'" + str(task_home) + "'\nsource_app=", 1)
    script.write_text(changed)

    def run(*arguments, expected=0, text=None):
        if text is not None:
            script.write_text(text)
        result = subprocess.run(['/bin/zsh', str(script), *arguments], text=True, capture_output=True)
        if expected == 0:
            assert result.returncode == 0, result.stdout + result.stderr
        else:
            assert result.returncode != 0, 'Expected failure'
        return result

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def job_state():
        return json.loads(jobs.read_text()) if jobs.exists() else {}

    run('--login', '--headphones')
    assert digest(app / 'Contents/MacOS/MoyaMusic') == digest(source_app / 'Contents/MacOS/MoyaMusic')
    assert len(job_state()) == 2
    headphone_job = next(value for key, value in job_state().items() if key.endswith('.headphones'))
    assert headphone_job['ProgramArguments'][0] == str(task_home / 'Library/Application Support/MoyaMusic/MoyaMusicHeadphones')
    assert Path(headphone_job['ProgramArguments'][0]).is_file()
    print('OK: fresh install, both startup modes, paths containing spaces and &')

    stale = app / 'Contents/Resources/obsolete-test-file'
    stale.write_text('old resource')
    run('--login', '--headphones')
    assert not stale.exists()
    assert not list(applications.glob('.moyamusic-install.*'))
    print('OK: updating replaces the whole bundle and removes obsolete resources')

    quit_marker.unlink(missing_ok=True)
    run('--configure-only')
    assert not quit_marker.exists()
    assert not job_state()
    print('OK: startup-only configuration leaves the running player alone')

    run('--configure-only', '--login')
    before = job_state()
    wrong_app = root / 'wrong.app'
    wrong_app.mkdir()
    (wrong_app / 'Contents').mkdir()
    with (wrong_app / 'Contents/Info.plist').open('wb') as file:
        plistlib.dump({'CFBundleIdentifier': 'another.application'}, file)
    protected_script = changed
    # The source path is composed from package_dir; override only that assignment for this case.
    protected_script = protected_script.replace('source_app="$package_dir/Моя музыка.app"', f'source_app="{wrong_app}"')
    run(expected=1, text=protected_script)
    assert job_state() == before
    assert not quit_marker.exists()
    print('OK: invalid source is rejected before closing the app or changing startup')

    replacement = root / 'move-failure'
    replacement.write_text('#!/bin/zsh\nif [[ "$1" == */new.app ]]; then exit 1; fi\nexec /bin/mv "$@"\n')
    replacement.chmod(0o755)
    prior_hash = digest(app / 'Contents/MacOS/MoyaMusic')
    run(expected=1, text=changed.replace('/bin/mv', str(replacement)))
    assert app.exists() and digest(app / 'Contents/MacOS/MoyaMusic') == prior_hash
    assert not list(applications.glob('.moyamusic-install.*'))
    assert job_state() == before
    print('OK: failed replacement restores the previous app')

    shutil.rmtree(app)
    run('--disable-autostart', text=changed)
    assert not job_state()
    assert not list((task_home / 'Library/LaunchAgents').glob('*.plist'))
    print('OK: disabling startup also works after removing the app')

    shutil.copytree(wrong_app, app)
    run(expected=1)
    with (app / 'Contents/Info.plist').open('rb') as file:
        assert plistlib.load(file)['CFBundleIdentifier'] == 'another.application'
    print('OK: a different app with the same name is preserved')
    ui_package = root / 'UI package'
    (ui_package / 'Исходники').mkdir(parents=True)
    arguments_file = root / 'ui-arguments.json'
    stub = ui_package / 'Исходники/install.sh'
    for name in ['Установить.command', 'Настроить автозапуск.command', 'Отключить автозапуск.command']:
        (ui_package / name).write_text((package / name).read_text().replace('/usr/bin/open', open_command))
    # The interactive script invokes its backend through zsh, so use a tiny shell backend.
    stub.write_text('#!/bin/zsh\nprint -r -- "$*" > ' + "'" + str(arguments_file) + "'\n")
    result = subprocess.run(['/bin/zsh', str(ui_package / 'Установить.command')], input='3\n', text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert arguments_file.read_text().strip() == '--login --headphones'
    result = subprocess.run(['/bin/zsh', str(ui_package / 'Настроить автозапуск.command')], input='2\n', text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert arguments_file.read_text().strip() == '--configure-only --login'
    result = subprocess.run(['/bin/zsh', str(ui_package / 'Отключить автозапуск.command')], input='', text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert arguments_file.read_text().strip() == '--disable-autostart'
    stub.write_text('#!/bin/zsh\nprint -- "Контрольная ошибка"\nexit 7\n')
    result = subprocess.run(['/bin/zsh', str(ui_package / 'Установить.command')], input='1\n', text=True, capture_output=True)
    assert result.returncode == 7 and 'Контрольная ошибка' in result.stdout and 'Действие не завершено' in result.stdout
    stub.write_text('#!/bin/zsh\nif [[ "$*" != *--configure-only* ]]; then exit 73; fi\nprint -r -- "$*" > ' + "'" + str(arguments_file) + "'\n")
    result = subprocess.run(['/bin/zsh', str(ui_package / 'Установить.command')], input='3\n\n', text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert arguments_file.read_text().strip() == '--configure-only --login --headphones'
    print('OK: double-click menus, visible errors, and Finder fallback without commands')
print('INSTALLER_CHECK_OK')
