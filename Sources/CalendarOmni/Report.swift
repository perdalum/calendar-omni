import Foundation
import Yams

struct ReportConfig {
    let calendars: [String]
    let fields: [EventField]
    let simple: Bool

    static func load(path: String) throws -> Self {
        let path = (path as NSString).expandingTildeInPath
        let text: String
        do { text = try String(contentsOfFile: path, encoding: .utf8) }
        catch { throw OmniError.input("Cannot read config '\(path)': \(error.localizedDescription)") }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> Self {
        do {
            guard let root = try Yams.compose(yaml: text), root.anchor == nil, root.tag == Tag(.map),
                  let mapping = root.mapping else {
                throw OmniError.input("Config must be a YAML mapping.")
            }
            var values: [String: Node] = [:]
            for (key, value) in mapping {
                guard key.anchor == nil, value.anchor == nil, key.tag == Tag(.str), let name = key.string, ["calendars", "fields", "datetime_format"].contains(name), values[name] == nil else {
                    throw OmniError.input("Unknown or duplicate config key: \(key.string ?? "<non-string>").")
                }
                values[name] = value
            }
            func strings(_ key: String) throws -> [String] {
                guard values[key]?.tag == Tag(.seq), let nodes = values[key]?.sequence else { throw OmniError.input("\(key) must be a nonempty list of strings.") }
                let strings = nodes.compactMap { $0.anchor == nil && $0.tag == Tag(.str) ? $0.string : nil }
                guard !strings.isEmpty, strings.count == nodes.count,
                      strings.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                      Set(strings).count == strings.count else {
                    throw OmniError.input("\(key) must contain unique, nonempty strings.")
                }
                return strings
            }
            let calendars = try strings("calendars"), names = try strings("fields")
            let fields = names.compactMap(EventField.init(rawValue:))
            guard fields.count == names.count else { throw OmniError.input("Unknown field in config.") }
            let style = values["datetime_format"]?.string ?? (values["datetime_format"] == nil ? "full" : "")
            guard (values["datetime_format"] == nil || values["datetime_format"]?.tag == Tag(.str)), ["simple", "full"].contains(style) else { throw OmniError.input("datetime_format must be simple or full.") }
            return Self(calendars: calendars, fields: fields, simple: style == "simple")
        } catch let error as OmniError { throw error }
        catch { throw OmniError.input("Invalid YAML config: \(error.localizedDescription)") }
    }
}

enum ReportPeriod {
    case today, tomorrow, lastWeek

    func range(now: Date, dates: DateParsing) -> (Date, Date) {
        let calendar = dates.calendar
        let today = calendar.startOfDay(for: now)
        let offset: Int
        switch self {
        case .today: offset = 0
        case .tomorrow: offset = 1
        case .lastWeek: offset = -((calendar.component(.weekday, from: today) + 5) % 7) - 7
        }
        let start = calendar.date(byAdding: .day, value: offset, to: today)!
        return (start, calendar.date(byAdding: .day, value: self == .lastWeek ? 7 : 1, to: start)!)
    }

    func data(records: [EventRecord], config: ReportConfig, dates: DateParsing) throws -> Data {
        func instant(_ text: String) throws -> Date {
            try text.count == 10 ? dates.day(text) : DateParsing.timestamp(text)
        }
        let keyed = try records.enumerated().map { (index, record) in
            (try instant(record.start), try instant(record.end), index, record)
        }
        let ordered = keyed.sorted { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }.map { $0.3 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = dates.calendar
        formatter.timeZone = dates.zone
        formatter.dateFormat = self == .lastWeek ? "yyyy-MM-dd HH:mm" : "HH:mm"
        func display(_ text: String) throws -> String {
            guard config.simple else { return text }
            if text.count == 10 { return self == .lastWeek ? text : "all-day" }
            return try formatter.string(from: instant(text))
        }
        if self != .lastWeek {
            return Data(try ordered.map {
                let title = $0.title.replacingOccurrences(of: #"[\r\n\x{0085}\x{2028}\x{2029}]+"#, with: " ", options: .regularExpression)
                return try "\(display($0.start)) -- \(display($0.end)) : \(title)\n"
            }.joined().utf8)
        }
        let formatted = try ordered.map {
            EventRecord(reference: $0.reference, title: $0.title, start: try display($0.start), end: try display($0.end),
                        location: $0.location, attendees: $0.attendees, notes: $0.notes)
        }
        return try OutputWriter.data(EventOutput(command: "extract", zone: dates.zone, fields: config.fields, records: formatted), format: .csv)
    }
}
