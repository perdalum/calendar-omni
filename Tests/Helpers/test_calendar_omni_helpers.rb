# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'stringio'
require_relative '../../scripts/calendar_omni_helpers'

class CalendarOmniHelpersTest < Minitest::Test
  H = CalendarOmniHelpers
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @dir = Dir.mktmpdir('calendar-omni-helpers-')
    @binary = File.join(@dir, 'CalendarOmni')
    File.write(@binary, <<~'FAKE')
      #!/usr/bin/ruby
      require 'json'
      dir = File.dirname(__FILE__)
      File.open(File.join(dir, 'calls.jsonl'), 'a') { |f| f.puts(JSON.generate(ARGV)) }
      unless ARGV[0] == 'extract' && ARGV.include?('--include-recurring')
        warn 'Expected read-only extraction with recurring events included'; exit 2
      end
      name = ARGV[ARGV.index('--calendar') + 1]
      if name == 'failure'
        warn 'Calendar permission denied'; exit 1
      end
      if name == 'malformed'
        puts 'not json'; exit 0
      end
      fields = ARGV[ARGV.index('--fields') + 1].split(',')
      fixtures = JSON.parse(File.read(File.join(dir, 'fixtures.json')))
      events = fixtures.fetch(name, []).map { |event| event.select { |key, _| fields.include?(key) } }
      puts JSON.generate('schemaVersion' => 1, 'command' => 'extract', 'timeZone' => 'Europe/Copenhagen', 'fields' => fields, 'events' => events)
    FAKE
    File.chmod(0o755, @binary)
    File.write(File.join(@dir, 'fixtures.json'), '{}')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def config(calendars = %w[first second], fields = H::FIELDS, datetime_format: 'full')
    { 'calendars' => calendars, 'fields' => fields, 'datetime_format' => datetime_format }
  end

  def event(title, start, ending = start)
    { 'title' => title, 'start' => start, 'end' => ending, 'location' => nil,
      'attendees' => [], 'notes' => "Line one; \"quoted\"\nLine two" }
  end

  def fixtures(values)
    File.write(File.join(@dir, 'fixtures.json'), JSON.generate(values))
  end

  def rows(csv)
    CSV.parse(csv, col_sep: ';', headers: true)
  end

  def calls
    File.readlines(File.join(@dir, 'calls.jsonl')).map { |line| JSON.parse(line) }
  end

  def test_ranges_today_tomorrow_and_previous_complete_week
    today = Date.new(2026, 9, 20) # Sunday
    assert_equal [today, today], H.date_range('today', today)
    assert_equal [today + 1, today + 1], H.date_range('tomorrow', today)
    assert_equal [Date.new(2026, 9, 7), Date.new(2026, 9, 13)], H.date_range('last-week', today)
    assert_equal [Date.new(2026, 9, 14), Date.new(2026, 9, 20)], H.date_range('last-week', today + 1)
    assert_equal [Date.new(2025, 12, 22), Date.new(2025, 12, 28)], H.date_range('last-week', Date.new(2026, 1, 1))
    assert_equal [Date.new(2027, 1, 1)] * 2, H.date_range('tomorrow', Date.new(2026, 12, 31))
  end

  def test_week_spanning_dst_still_has_seven_civil_days
    assert_equal [Date.new(2026, 3, 23), Date.new(2026, 3, 29)], H.date_range('last-week', Date.new(2026, 3, 30))
    assert_equal [Date.new(2026, 10, 19), Date.new(2026, 10, 25)], H.date_range('last-week', Date.new(2026, 10, 26))
  end

  def test_yaml_and_validation
    path = File.join(@dir, 'config')
    File.write(path, "# My calendars\ncalendars: [Ugeplan, 'Komme-gå']\nfields:\n  - notes\n  - title\n")
    assert_equal config(['Ugeplan', 'Komme-gå'], %w[notes title]), H.load_config(path)
    ["calendars: []\nfields: [title]", "calendars: [A, A]\nfields: [title]",
     "calendars: [A]\nfields: [title, title]", "calendars: [A]\nfields: [invalid]",
     "calendars: [A]\nfields: [title]\nunknown: yes", "calendars: [A]\ncalendars: [B]\nfields: [title]",
     "calendars: [A]\nfields: []", "calendars: [A]\nfields: title",
     "calendars: &cal [A]\nfields: *cal", "--- !ruby/object:Object {}", "---\n---\n"].each do |source|
      File.write(path, source)
      assert_raises(H::Failure, source) { H.load_config(path) }
    end
    assert_raises(H::Failure) { H.load_config(File.join(@dir, 'missing')) }
  end

  def test_merge_sorts_actual_instants_not_timestamp_text
    fixtures('first' => [event('later', '2026-09-20T09:00:00Z'), event('first', '2026-09-20T09:00:00+02:00')],
             'second' => [event('middle', '2026-09-20T08:00:00Z')])
    result = rows(H.report('last-week', config, @binary, today: Date.new(2026, 9, 20)))
    assert_equal %w[first middle later], result.map { |r| r['title'] }
    assert_equal H::FIELDS, result.headers
    assert_equal "Line one; \"quoted\"\nLine two", result[0]['notes']
    assert_equal [], JSON.parse(result[0]['attendees'])
    assert_equal '', result[0]['location'].to_s
    assert_equal 2, calls.length
  end

  def test_sorting_when_dates_are_not_displayed
    fixtures('first' => [event('later', '2026-09-20T13:00:00Z')], 'second' => [event('earlier', '2026-09-20T11:00:00Z')])
    result = H.report('tomorrow', config(%w[first second], ['notes']), @binary, today: Date.new(2026, 9, 19)).lines
    assert_equal %w[earlier later], result.map { |line| line.split(' : ', 2).last.strip }
    calls.each do |args|
      assert_equal '2026-09-20', args[args.index('--from') + 1]
      assert_equal '2026-09-20', args[args.index('--to') + 1]
      assert_equal 'title,start,end', args[args.index('--fields') + 1]
      assert_includes args, '--include-recurring'
    end
  end

  def test_all_day_and_fractional_instants
    today = Date.new(2026, 9, 20)
    midnight = Time.local(today.year, today.month, today.day)
    fixtures('first' => [event('timed', (midnight + 3600).iso8601)],
             'second' => [event('all-day', today.iso8601, (today + 1).iso8601)])
    result = rows(H.report('last-week', config, @binary, today: today))
    assert_equal ['all-day', 'timed'], result.map { |r| r['title'] }
    assert_operator H.instant('2026-09-20T09:00:00.123456789Z'), :>, H.instant('2026-09-20T09:00:00.123456788Z')
  end

  def test_empty_calendars_emit_one_header
    assert_equal "title;start;end;location;attendees;notes\r\n", H.report('last-week', config, @binary, today: Date.new(2026, 9, 20))
    calls.each do |args|
      assert_equal '2026-09-07', args[args.index('--from') + 1]
      assert_equal '2026-09-13', args[args.index('--to') + 1]
    end
  end

  def test_failure_is_nonzero_without_partial_stdout
    fixtures('first' => [event('must not leak', '2026-09-20T09:00:00Z')])
    path = File.join(@dir, 'config')
    File.write(path, YAML.dump(config(%w[first failure])))
    stdout, stderr, status = Open3.capture3(File.join(ROOT, 'scripts/today'), '--config', path, '--binary', @binary)
    assert_equal 1, status.exitstatus
    assert_empty stdout
    assert_includes stderr, 'Calendar permission denied'
  end

  def test_invalid_json_fails_instead_of_empty_report
    error = assert_raises(H::Failure) { H.report('today', config(['malformed']), @binary) }
    assert_equal 1, error.status
  end

  def test_calendar_names_are_passed_as_arguments_without_a_shell
    name = 'Calendar $(touch injected-file); "quoted"'
    H.report('today', config([name], ['title']), @binary)
    assert_equal name, calls.first[calls.first.index('--calendar') + 1]
    refute File.exist?(File.join(ROOT, 'injected-file'))
  end

  def test_helpers_work_from_another_directory_and_via_symlink
    path = File.join(@dir, 'config')
    File.write(path, YAML.dump(config(['first'], ['title'])))
    link = File.join(@dir, 'today-link')
    File.symlink(File.join(ROOT, 'scripts/today'), link)
    stdout, stderr, status = Open3.capture3(link, '--config', path, '--binary', @binary, chdir: @dir)
    assert status.success?, stderr
    assert_empty stdout
    %w[today tomorrow last-week].each do |name|
      stdout, stderr, status = Open3.capture3(File.join(ROOT, 'scripts', name), '--help', chdir: @dir)
      assert status.success?, stderr
      assert_includes stdout, "Usage: #{name}"
    end
  end

  def test_missing_config_and_bad_options_have_exit_two
    stdout, stderr, status = Open3.capture3(File.join(ROOT, 'scripts/today'), '--config', File.join(@dir, 'missing'))
    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_includes stderr, 'Config not found'
    stdout, _stderr, status = Open3.capture3(File.join(ROOT, 'scripts/today'), '--unexpected')
    assert_equal 2, status.exitstatus
    assert_empty stdout
  end
  def test_datetime_config_accepts_only_simple_or_full_and_defaults_to_full
    path = File.join(@dir, 'format-config')
    prefix = "calendars: [first]\nfields: [start, end]\n"
    File.write(path, prefix)
    assert_equal 'full', H.load_config(path)['datetime_format']
    %w[simple full].each do |format|
      File.write(path, prefix + "datetime_format: #{format}\n")
      assert_equal format, H.load_config(path)['datetime_format']
    end
    ['short', '', 'null', 'true', '[simple]', '42', 'Full'].each do |format|
      File.write(path, prefix + "datetime_format: #{format}\n")
      assert_raises(H::Failure) { H.load_config(path) }
    end
  end

  def test_simple_daily_and_weekly_formats_without_offsets_or_seconds
    start = Time.local(2026, 9, 20, 9, 15, 49).iso8601(3)
    ending = Time.local(2026, 9, 20, 10, 45, 59).iso8601(3)
    fixtures('first' => [event('Meeting', start, ending)])
    settings = config(['first'], %w[start end], datetime_format: 'simple')
    %w[today tomorrow].each do |mode|
      assert_equal "09:15 -- 10:45 : Meeting\n", H.report(mode, settings, @binary)
    end
    result = rows(H.report('last-week', settings, @binary))[0]
    assert_equal '2026-09-20 09:15', result['start']
    assert_equal '2026-09-20 10:45', result['end']
  end

  def test_full_format_preserves_exact_values_for_all_helpers
    start = '2026-09-20T09:15:49.123456789+02:00'
    ending = '2026-09-20T10:45:59+02:00'
    fixtures('first' => [event('Meeting', start, ending)])
    %w[today tomorrow last-week].each do |mode|
      output = H.report(mode, config(['first'], %w[start end]), @binary)
      if mode == 'last-week'
        assert_equal start, rows(output)[0]['start']
        assert_equal ending, rows(output)[0]['end']
      else
        assert_equal "#{start} -- #{ending} : Meeting\n", output
      end
    end
  end

  def test_all_day_dates_are_not_invented_times
    fixtures('first' => [event('All day', '2026-09-20', '2026-09-21')])
    simple = config(['first'], %w[start end], datetime_format: 'simple')
    %w[today tomorrow].each do |mode|
      assert_equal "all-day -- all-day : All day\n", H.report(mode, simple, @binary)
    end
    %w[start end].zip(%w[2026-09-20 2026-09-21]).each do |field, expected|
      assert_equal expected, rows(H.report('last-week', simple, @binary))[0][field]
      assert_equal expected, rows(H.report('last-week', config(['first']), @binary))[0][field]
    end
  end

  def test_simple_format_does_not_change_chronological_sorting
    fixtures('first' => [event('later', '2026-09-20T09:00:00Z')],
             'second' => [event('earlier', '2026-09-20T09:30:00+02:00')])
    settings = config(%w[first second], %w[title start], datetime_format: 'simple')
    result = H.report('today', settings, @binary).lines
    assert_equal %w[earlier later], result.map { |line| line.split(' : ', 2).last.strip }
    assert_equal Time.iso8601('2026-09-20T09:30:00+02:00').getlocal.strftime('%H:%M'), result[0].split(' -- ').first
    assert_equal Time.iso8601('2026-09-20T09:00:00Z').getlocal.strftime('%H:%M'), result[1].split(' -- ').first
  end

  def test_daily_fixed_layout_flattens_titles_and_ignores_configured_columns
    start = Time.local(2026, 9, 20, 9, 0).iso8601
    ending = Time.local(2026, 9, 20, 10, 30).iso8601
    fixtures('first' => [event("Møde; \"rapport\"\r\nAnden linje\u2028slut", start, ending)])
    settings = config(['first'], ['attendees'], datetime_format: 'simple')
    %w[today tomorrow].each do |mode|
      assert_equal "09:00 -- 10:30 : Møde; \"rapport\" Anden linje slut\n", H.report(mode, settings, @binary)
    end
    calls.each { |args| assert_equal 'title,start,end', args[args.index('--fields') + 1] }
  end

  def test_empty_daily_reports_have_no_header_or_blank_line
    %w[today tomorrow].each { |mode| assert_equal '', H.report(mode, config, @binary) }
  end

end
