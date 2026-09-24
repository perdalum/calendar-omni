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
            guard fields.count == names.count, fields.allSatisfy({ EventField.contentFields.contains($0) }) else { throw OmniError.input("Unknown field in config.") }
            let style = values["datetime_format"]?.string ?? (values["datetime_format"] == nil ? "full" : "")
            guard (values["datetime_format"] == nil || values["datetime_format"]?.tag == Tag(.str)), ["simple", "full"].contains(style) else { throw OmniError.input("datetime_format must be simple or full.") }
            return Self(calendars: calendars, fields: fields, simple: style == "simple")
        } catch let error as OmniError { throw error }
        catch { throw OmniError.input("Invalid YAML config: \(error.localizedDescription)") }
    }
}

enum ReportPeriod {
    case today, tomorrow, lastWeek

    static func shortLocation(_ location: String?) -> String {
        guard let line = location?.split(whereSeparator: { $0.isNewline }).first else { return "" }
        let text = line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        // AU room descriptions commonly begin with a building-floor.room code.
        if let room = text.range(of: #"\b\d{4}-\d{2}\.\d{3}\b"#, options: .regularExpression) {
            return String(text[room])
        }
        return text.count > 40 ? String(text.prefix(39)) + "…" : text
    }

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

    func data(records: [EventRecord], simple: Bool = false, dates: DateParsing) throws -> Data {
        func instant(_ text: String) throws -> Date {
            try text.count == 10 ? dates.day(text) : DateParsing.timestamp(text)
        }
        let keyed = try records.enumerated().map { (index, record) in
            (try instant(record.start), try instant(record.end), index, record)
        }
        let ordered = keyed.sorted { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }.map { $0.3 }
        if self == .lastWeek {
            let events: [[String: Any]] = ordered.map {
                ["title": $0.title, "start": $0.start, "end": $0.end,
                 "location": $0.location as Any? ?? NSNull(),
                 "attendees": $0.attendees.compactMap { attendee in
                     attendee.name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                 }]
            }
            var data = try JSONSerialization.data(withJSONObject: events,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            data.append(10)
            return data
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = dates.calendar
        formatter.timeZone = dates.zone
        formatter.dateFormat = "HH:mm"
        func display(_ text: String) throws -> String {
            guard simple else { return text }
            if text.count == 10 { return "all-day" }
            return try formatter.string(from: instant(text))
        }
        return Data(try ordered.map {
            let title = $0.title.replacingOccurrences(of: #"[\r\n\x{0085}\x{2028}\x{2029}]+"#, with: " ", options: .regularExpression)
            // EventKit gives display names, not structured given names. Use the
            // first whitespace-separated part, preserving hyphenated names.
            let names: [String] = self == .today ? $0.attendees.compactMap {
                guard let name = $0.name else { return nil }
                let parts = name.split(whereSeparator: { $0.isWhitespace })
                guard parts.joined(separator: " ").caseInsensitiveCompare("Per Møldrup-Dalum") != .orderedSame else { return nil }
                return parts.first.map(String.init)
            } : []
            let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " og " + names.last! : names.joined()
            let suffix = list.isEmpty ? "" : " med \(list)"
            let location = self == .today ? Self.shortLocation($0.location) : ""
            let place = location.isEmpty ? "" : " — \(location)"
            return try "\(display($0.start)) -- \(display($0.end)) : \(title)\(suffix)\(place)\n"
        }.joined().utf8)
    }
}
