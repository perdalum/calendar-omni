# frozen_string_literal: true

require 'csv'
require 'date'
require 'json'
require 'open3'
require 'optparse'
require 'time'
require 'yaml'

# Shared implementation for the three small personal reporting commands.
module CalendarOmniHelpers
  FIELDS = %w[title start end location attendees notes].freeze
  MODES = %w[today tomorrow last-week].freeze

  class Failure < StandardError
    attr_reader :status
    def initialize(message, status = 2)
      super(message)
      @status = status
    end
  end

  def self.load_config(path)
    source = File.read(path, encoding: 'UTF-8')
    # Reject duplicate top-level keys instead of silently accepting YAML's last value.
    stream = Psych.parse_stream(source)
    raise Failure, 'Config must contain exactly one YAML document.' unless stream.children.length == 1
    mapping = stream.children.first.root
    unless mapping.is_a?(Psych::Nodes::Mapping)
      raise Failure, 'Config must be a YAML mapping with calendars and fields lists.'
    end
    keys = mapping.children.each_slice(2).map { |key, _| key.respond_to?(:value) ? key.value : nil }
    raise Failure, 'Duplicate config keys are not allowed.' unless keys.uniq == keys
    config = YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
    unless config.is_a?(Hash) && (%w[calendars fields] - config.keys).empty? &&
           (config.keys - %w[calendars fields datetime_format]).empty?
      raise Failure, 'Config requires calendars and fields; datetime_format is optional.'
    end
    %w[calendars fields].each do |key|
      values = config[key]
      unless values.is_a?(Array) && !values.empty? && values.all? { |v| v.is_a?(String) && !v.strip.empty? }
        raise Failure, "#{key} must be a nonempty list of strings."
      end
      raise Failure, "Duplicate entries in #{key} are not allowed." unless values.uniq == values
    end
    unknown = config['fields'] - FIELDS
    raise Failure, "Unknown fields: #{unknown.join(', ')}. Choose from #{FIELDS.join(', ')}." unless unknown.empty?
    config['datetime_format'] = 'full' unless config.key?('datetime_format')
    unless %w[simple full].include?(config['datetime_format'])
      raise Failure, 'datetime_format must be simple or full.'
    end
    config
  rescue Errno::ENOENT
    raise Failure, "Config not found: #{path}. Copy examples/calendar-omni.yaml to ~/.calendar-omni and edit it."
  rescue Psych::Exception, ArgumentError => e
    raise Failure, "Invalid YAML config: #{e.message}"
  rescue SystemCallError => e
    raise Failure, "Cannot read config: #{e.message}"
  end

  def self.date_range(mode, today = Date.today)
    case mode
    when 'today' then [today, today]
    when 'tomorrow' then [today + 1, today + 1]
    when 'last-week'
      monday = today - (today.cwday - 1) - 7
      [monday, monday + 6]
    else raise Failure, "Unknown report: #{mode}"
    end
  end

  def self.executable(explicit = nil)
    if explicit
      path = File.expand_path(explicit)
      return path if File.file?(path) && File.executable?(path)
      raise Failure, "CalendarOmni executable not found or not executable: #{path}"
    end
    # Prefer the installed version; otherwise the local Release build makes these
    # scripts immediately usable from this checkout, independently of the cwd.
    candidates = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'CalendarOmni') }
    candidates << File.expand_path('../build/Build/Products/Release/CalendarOmni', __dir__)
    found = candidates.find { |path| File.file?(path) && File.executable?(path) }
    return File.expand_path(found) if found
    raise Failure, 'CalendarOmni was not found. Build Release, put CalendarOmni on PATH, or use --binary PATH.'
  end

  def self.instant(value)
    raise Failure.new('CalendarOmni returned a non-string date.', 1) unless value.is_a?(String)
    if /\A\d{4}-\d{2}-\d{2}\z/.match?(value)
      date = Date.iso8601(value)
      # An all-day event sorts at local midnight on its original start date.
      Time.local(date.year, date.month, date.day).to_r
    elsif /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/.match?(value)
      Time.iso8601(value).to_r
    else
      raise ArgumentError, "Unexpected date format: #{value.inspect}"
    end
  rescue ArgumentError => e
    raise Failure.new("CalendarOmni returned an invalid date: #{e.message}", 1)
  end

  def self.report(mode, config, binary, today: Date.today, stderr: $stderr)
    first, last = date_range(mode, today)
    daily = %w[today tomorrow].include?(mode)
    # Daily reports have a fixed layout; configurable columns apply to weekly CSV.
    fetch_fields = daily ? %w[title start end] : (config['fields'] + %w[start end]).uniq
    combined = []
    config['calendars'].each_with_index do |calendar, calendar_index|
      args = [binary, 'extract', '--calendar', calendar, '--from', first.iso8601,
              '--to', last.iso8601, '--include-recurring', '--fields', fetch_fields.join(','), '--format', 'json']
      stdout, diagnostics, status = Open3.capture3(*args)
      unless status.success?
        code = status.exitstatus == 2 ? 2 : 1
        raise Failure.new("CalendarOmni failed for #{calendar.inspect} (exit #{status.exitstatus || 'signal'}).\n#{diagnostics.strip}", code)
      end
      stderr.write(diagnostics) unless diagnostics.empty?
      payload = JSON.parse(stdout)
      unless payload.is_a?(Hash) && payload['schemaVersion'] == 1 && payload['command'] == 'extract' &&
             payload['fields'] == fetch_fields && payload['events'].is_a?(Array)
        raise Failure.new("Unexpected CalendarOmni JSON response for #{calendar.inspect}.", 1)
      end
      payload['events'].each_with_index do |event, event_index|
        unless event.is_a?(Hash) && fetch_fields.all? { |field| event.key?(field) }
          raise Failure.new("CalendarOmni returned an incomplete event for #{calendar.inspect}.", 1)
        end
        fetch_fields.each do |field|
          value = event[field]
          valid = if field == 'attendees'
                    value.is_a?(Array) && value.all? do |attendee|
                      attendee.is_a?(Hash) && attendee.keys.sort == %w[name url] &&
                        (attendee['name'].nil? || attendee['name'].is_a?(String)) && attendee['url'].is_a?(String)
                    end
                  elsif %w[location notes].include?(field)
                    value.nil? || value.is_a?(String)
                  else
                    value.is_a?(String)
                  end
          raise Failure.new("Invalid #{field} value returned by CalendarOmni.", 1) unless valid
        end
        combined << [[instant(event['start']), instant(event['end']), calendar_index, event_index], event]
      end
    end
    combined.sort_by!(&:first)
    if daily
      format = config.fetch('datetime_format', 'full')
      return combined.map do |_, event|
        from = display_datetime(event['start'], mode, format)
        to = display_datetime(event['end'], mode, format)
        title = event['title'].gsub(/[\r\n\u0085\u2028\u2029]+/, ' ')
        "#{from} -- #{to} : #{title}\n"
      end.join
    end
    CSV.generate(col_sep: ';', row_sep: "\r\n", encoding: 'UTF-8') do |csv|
      csv << config['fields']
      combined.each do |_, event|
        csv << config['fields'].map do |field|
          if field == 'attendees'
            JSON.generate(event[field])
          elsif %w[start end].include?(field)
            display_datetime(event[field], mode, config.fetch('datetime_format', 'full'))
          else
            event[field]
          end
        end
      end
    end
  rescue JSON::ParserError => e
    raise Failure.new("CalendarOmni returned malformed JSON: #{e.message}", 1)
  rescue SystemCallError => e
    raise Failure.new("Cannot run CalendarOmni: #{e.message}", 1)
  end

  def self.display_datetime(value, mode, format)
    return value if format == 'full'
    daily = %w[today tomorrow].include?(mode)
    # Date-only EventKit values are all-day boundaries, not timed appointments.
    return daily ? 'all-day' : value if /\A\d{4}-\d{2}-\d{2}\z/.match?(value)
    Time.iso8601(value).getlocal.strftime(daily ? '%H:%M' : '%Y-%m-%d %H:%M')
  end

  def self.run(mode, argv = ARGV)
    config_path = File.expand_path('~/.calendar-omni')
    binary_path = nil
    parser = OptionParser.new do |options|
      layout = mode == 'last-week' ? 'semicolon CSV' : 'FROM -- TO : TITLE lines'
      options.banner = "Usage: #{mode} [--config PATH] [--binary PATH]\n\nMerge configured calendars into chronological #{layout} (including recurring events)."
      options.on('--config PATH', 'YAML config; defaults to ~/.calendar-omni.') { |value| config_path = File.expand_path(value) }
      options.on('--binary PATH', 'Use this CalendarOmni executable instead of PATH/local Release.') { |value| binary_path = value }
      options.on('-h', '--help', 'Show help; no Calendar access.') { puts options; return 0 }
    end
    parser.parse!(argv)
    raise Failure, "Unexpected arguments: #{argv.join(' ')}" unless argv.empty?
    config = load_config(config_path)
    binary = executable(binary_path)
    # Capture the civil date once so crossing midnight cannot split the report range.
    output = report(mode, config, binary, today: Date.today)
    $stdout.write(output)
    0
  rescue OptionParser::ParseError, Failure => e
    $stderr.puts("#{mode}: #{e.message}")
    e.is_a?(Failure) ? e.status : 2
  rescue SystemCallError, IOError => e
    $stderr.puts("#{mode}: #{e.message}")
    1
  rescue Interrupt
    130
  end
end
