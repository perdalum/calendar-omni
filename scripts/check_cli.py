#!/usr/bin/env python3
"""Exercise the built CLI without requesting Calendar access or writing events."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else 'build/Build/Products/Release/CalendarOmni').resolve())
checks = 0


def run(args, expected=0, stdin=None):
    global checks
    result = subprocess.run([binary, *args], input=stdin, capture_output=True, timeout=15)
    assert result.returncode == expected, (args, result.returncode, result.stderr.decode(errors='replace'))
    if expected:
        assert not result.stdout, (args, 'error polluted stdout')
        assert result.stderr, (args, 'missing diagnostic')
    checks += 1
    return result


assert run(['--version']).stdout.strip() == b'1.1.0'
for command in [[], ['--help'], ['extract', '--help'], ['create', '--help'], ['update', '--help']]:
    run(command)
with tempfile.TemporaryDirectory() as directory:
    config = Path(directory) / 'config with spaces.yaml'
    for command in ['today', 'tomorrow', 'last-week']:
        assert b'--config' in run([command, '--help']).stdout
        run([command, '--config', str(Path(directory) / 'missing')], 2)
        config.write_text('calendars: []\nfields: [title]\n')
        run([command, '--config', str(config)], 2)
        run([command, '--binary', binary], 2)
extract_help = run(['extract', '--help']).stdout
assert b'--include-recurring' in extract_help
assert b'--only-meetings' in extract_help
base = ['extract', '--calendar', 'NoAccessNeeded', '--from', '2026-09-01', '--to', '2026-09-30']
for tail in [['--fields', 'none'], ['--fields', 'title,title'], ['--fields', 'title,'], ['--filter', ''], ['--regex', '['], ['--filter', 'x', '--regex', 'x'], ['--format', 'xml'], ['--time-zone', 'Unknown/Zone'], ['--include-recurring', 'true'], ['--only-meetings', 'true'], ['--unexpected']]:
    run(base + tail, 2)
run(['extract', '--from', '2026-09-01', '--to', '2026-09-30'], 2)
run(['extract', '--calendar', 'x', '--from', '2026-09-30', '--to', '2026-09-01'], 2)
run(['extract', '--calendar', 'x', '--from', '2026-02-30', '--to', '2026-09-01'], 2)
create = ['create', '--calendar', 'NoAccessNeeded', '--title', 'Title', '--date', '2026-09-21', '--start', '09:00']
for tail in [[], ['--duration', '0m'], ['--end', '08:00'], ['--end', '10:00', '--duration', '1h'], ['--duration', '1h', '--notes', 'x', '--notes-stdin'], ['--duration', '1h', '--attendees', 'x']]:
    run(create + tail, 2)
run(['create', '--calendar', 'x', '--title', 'x', '--date', '2026-03-29', '--start', '02:30', '--duration', '1h', '--time-zone', 'Europe/Copenhagen'], 2)
run(['create', '--calendar', 'x', '--title', 'x', '--date', '2026-10-25', '--start', '02:30', '--duration', '1h', '--time-zone', 'Europe/Copenhagen'], 2)
run(['update', '--input', '-'], 2, b'not json')
run(['update', '--input', '-'], 2, b'\xff')
run(['update', '--input', '-'], 2, b'{}')
empty = {'schemaVersion': 1, 'command': 'extract', 'timeZone': 'Europe/Copenhagen', 'fields': ['title'], 'events': []}
result = run(['update', '--input', '-'], stdin=json.dumps(empty).encode())
parsed = json.loads(result.stdout)
assert parsed['command'] == 'update' and parsed['events'] == []
assert parsed['fields'] == ['title', 'start', 'end', 'location', 'attendees', 'notes']
csv = run(['update', '--input', '-', '--format', 'csv'], stdin=json.dumps(empty).encode())
assert csv.stdout == b'title;start;end;location;attendees;notes\r\n'
try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError:
    print('JSON Schema validation skipped: install jsonschema[format] to enable it.')
else:
    root = Path(__file__).resolve().parents[1]
    for name, value in [('CalendarOmni.schema.json', parsed), ('CalendarOmni.update.schema.json', empty)]:
        schema = json.loads((root / name).read_text())
        Draft202012Validator.check_schema(schema)
        Draft202012Validator(schema, format_checker=FormatChecker()).validate(value)
    print('Output and update-input schemas validated.')
print(f'{checks} CLI checks passed; no calendar access or writes requested.')
