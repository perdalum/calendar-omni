#!/usr/bin/env python3
"""Read-only fixture checks through the user's continued WSTP kernel.
Requires wolframscript, ~/wstp-profile, and Ruby (only for output comparison).
"""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
WLF = ['wolframscript', '-wstpserver', '-continueprofile', str(Path.home() / 'wstp-profile'), '-file']


def run(args):
    return subprocess.run(args, cwd=ROOT, capture_output=True, timeout=30)


def native(mode, *args):
    return run(WLF + [str(ROOT / 'scripts' / (mode + '.wls')), *args])


with tempfile.TemporaryDirectory(prefix='calendar-omni-wl-') as directory:
    folder = Path(directory)
    binary = folder / 'CalendarOmni'
    binary.write_text('''#!/usr/bin/env python3
import json, pathlib, sys
args = sys.argv[1:]
assert args[0] == 'extract' and '--include-recurring' in args
calendar = args[args.index('--calendar') + 1]
with open(pathlib.Path(__file__).with_name('calls.jsonl'), 'a') as f:
    f.write(json.dumps(args) + '\\n')
if calendar == 'failure':
    print('Fixture failure', file=sys.stderr); sys.exit(1)
if calendar == 'malformed':
    print('bad json'); sys.exit(0)
fields = args[args.index('--fields') + 1].split(',')
event = dict(title='Møde; "quoted"\\nsecond', start='2026-09-20T07:30:00Z', end='2026-09-20T08:30:00Z', location=None, notes='Notes;\\nline', attendees=[])
if calendar == 'second':
    event.update(title='Earlier', start='2026-09-20T09:00:00+02:00', end='2026-09-20T09:15:00+02:00')
events = [] if calendar == 'empty' else [{f: event[f] for f in fields}]
print(json.dumps(dict(schemaVersion=1, command='extract', timeZone='Europe/Copenhagen', fields=fields, events=events), ensure_ascii=False))
''', encoding='utf-8')
    binary.chmod(0o755)
    config = folder / 'config with spaces.yaml'
    checks = 0
    for style in ['simple', 'full']:
        config.write_text('calendars: ["Komme-gå $(nothing)", second]\nfields: [title, start, end, location, attendees, notes]\ndatetime_format: ' + style + '\n', encoding='utf-8')
        for mode in ['today', 'tomorrow', 'last-week']:
            wl = native(mode, 'config=' + str(config), 'binary=' + str(binary))
            ruby = run([str(ROOT / 'scripts' / mode), '--config', str(config), '--binary', str(binary)])
            assert wl.returncode == ruby.returncode == 0, (wl, ruby)
            assert wl.stdout == ruby.stdout, (mode, style, wl.stdout, ruby.stdout)
            checks += 1
    calls = [json.loads(line) for line in (folder / 'calls.jsonl').read_text().splitlines()]
    assert any('Komme-gå $(nothing)' in call for call in calls)
    checks += 1
    for mode in ['today', 'tomorrow', 'last-week']:
        assert native(mode, 'help').returncode == 0
        checks += 1
    for calendar in ['empty', 'failure', 'malformed']:
        config.write_text(f'calendars: ["{calendar}"]\nfields: [title]\n')
        result = native('today', 'config=' + str(config), 'binary=' + str(binary))
        assert result.returncode == (0 if calendar == 'empty' else 1), result
        if calendar == 'empty':
            assert result.stdout == b'', result
        else:
            assert b'M\xc3\xb8de' not in result.stdout, result
        checks += 1
    assert native('today', 'config=' + str(folder / 'missing')).returncode == 2
    checks += 1
    # A successful invocation after failures also checks continued-kernel reuse.
    assert native('today', 'help').returncode == 0
    checks += 1
    print(f'{checks} WSTP CLI checks passed; native/Ruby outputs match byte for byte.')
