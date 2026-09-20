import Foundation

enum OmniError: Error, LocalizedError {
    case input(String)
    case operation(String)

    var errorDescription: String? {
        switch self { case .input(let message), .operation(let message): message }
    }
}

struct DateParsing {
    let zone: TimeZone
    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "en_US_POSIX")
        result.timeZone = zone
        return result
    }

    static func timeZone(_ name: String?) throws -> TimeZone {
        guard let name else { return .current }
        guard (TimeZone.knownTimeZoneIdentifiers.contains(name) || ["UTC", "GMT"].contains(name)),
              let zone = TimeZone(identifier: name) else {
            throw OmniError.input("Unknown IANA time zone '\(name)'.")
        }
        return zone
    }

    func day(_ text: String) throws -> Date {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw OmniError.input("Invalid date '\(text)'; expected YYYY-MM-DD.")
        }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              dayString(date) == text else {
            throw OmniError.input("Invalid civil date '\(text)' in \(zone.identifier).")
        }
        return calendar.startOfDay(for: date)
    }

    func localTime(day text: String, clock: String) throws -> Date {
        let base = try day(text)
        guard clock.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil else {
            throw OmniError.input("Invalid time '\(clock)'; expected H:mm or HH:mm.")
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            throw OmniError.input("Invalid clock time '\(clock)'.")
        }
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        components.hour = parts[0]; components.minute = parts[1]; components.second = 0
        let anchor = base.addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: anchor, matching: components, matchingPolicy: .strict,
                                            repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: anchor, matching: components, matchingPolicy: .strict,
                                           repeatedTimePolicy: .last),
              calendar.isDate(first, inSameDayAs: base) else {
            throw OmniError.input("Local time \(text) \(clock) does not exist in \(zone.identifier).")
        }
        guard first == last else {
            throw OmniError.input("Local time \(text) \(clock) occurs twice in \(zone.identifier); choose an unambiguous time.")
        }
        return first
    }

    static func durationMinutes(_ text: String) throws -> Int {
        let regex = try NSRegularExpression(pattern: #"^(?:(\d+)[hH])?(?:(\d+)[mM])?$"#)
        let ns = text as NSString
        guard !text.isEmpty, let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            throw OmniError.input("Invalid duration '\(text)'; use 1h30m, 2h, or 45m.")
        }
        func part(_ index: Int) throws -> Int {
            let range = match.range(at: index)
            if range.location == NSNotFound { return 0 }
            guard let value = Int(ns.substring(with: range)) else { throw OmniError.input("Duration is too large.") }
            return value
        }
        let (hours, overflow1) = try part(1).multipliedReportingOverflow(by: 60)
        let (minutes, overflow2) = try hours.addingReportingOverflow(part(2))
        guard !overflow1, !overflow2, minutes > 0 else { throw OmniError.input("Duration must be positive and within range.") }
        return minutes
    }

    func creationDates(date: String, start: String, end: String?, duration: String?) throws -> (Date, Date) {
        guard (end == nil) != (duration == nil) else { throw OmniError.input("Supply exactly one of --end or --duration.") }
        let from = try localTime(day: date, clock: start)
        let to: Date
        if let end { to = try localTime(day: date, clock: end) }
        else {
            let minutes = try Self.durationMinutes(duration!)
            to = from.addingTimeInterval(Double(minutes) * 60)
        }
        guard to > from, to < Self.upperBound else { throw OmniError.input("End must be after start and before year 10000.") }
        return (from, to)
    }

    func range(from: String, to: String) throws -> (Date, Date) {
        let first = try day(from), last = try day(to)
        guard first <= last, let exclusive = calendar.date(byAdding: .day, value: 1, to: last), exclusive < Self.upperBound else {
            throw OmniError.input("Extraction dates must be ordered and end before 9999-12-31.")
        }
        return (first, exclusive)
    }

    func windows(from: Date, to: Date) -> [(Date, Date)] {
        var result: [(Date, Date)] = [], cursor = from
        while cursor < to {
            let next = min(calendar.date(byAdding: .year, value: 1, to: cursor) ?? to, to)
            result.append((cursor, next)); cursor = next
        }
        return result
    }

    func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func timestamp(_ date: Date) -> String {
        // Foundation's default fractional renderer can truncate to milliseconds.
        let seconds = date.timeIntervalSinceReferenceDate
        var whole = floor(seconds)
        var nanos = Int(((seconds - whole) * 1_000_000_000).rounded())
        if nanos == 1_000_000_000 { whole += 1; nanos = 0 }
        let base = Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .standard,
            timeSeparator: .colon, timeZoneSeparator: .colon,
            includingFractionalSeconds: false, timeZone: zone).format(Date(timeIntervalSinceReferenceDate: whole))
        guard nanos > 0 else { return base }
        var fraction = String(format: "%09d", nanos)
        while fraction.last == "0" { fraction.removeLast() }
        return String(base.prefix(19)) + "." + fraction + String(base.dropFirst(19))
    }

    static let upperBound = Date(timeIntervalSince1970: 253402300800)

    static func timestamp(_ text: String) throws -> Date {
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#
        guard text.range(of: pattern, options: .regularExpression) != nil else {
            throw OmniError.input("Invalid timestamp '\(text)'; use RFC 3339 with an explicit offset.")
        }
        // Validate civil components independently; ISO parsers can normalize invalid dates.
        let dateText = String(text.prefix(10))
        _ = try DateParsing(zone: TimeZone(secondsFromGMT: 0)!).day(dateText)
        let timeParts = String(text.dropFirst(11).prefix(8)).split(separator: ":").compactMap { Int($0) }
        guard timeParts.count == 3, timeParts[0] < 24, timeParts[1] < 60, timeParts[2] < 60 else {
            throw OmniError.input("Invalid timestamp clock components.")
        }
        if !text.hasSuffix("Z") {
            let offset = text.suffix(5).split(separator: ":").compactMap { Int($0) }
            guard offset.count == 2, offset[0] < 24, offset[1] < 60, !text.hasSuffix("-00:00") else {
                throw OmniError.input("Timestamp needs a known, valid UTC offset.")
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let tail = String(text.dropFirst(19))
        let fractionDigits = tail.hasPrefix(".") ? String(tail.dropFirst().prefix(while: { $0.isNumber })) : ""
        let suffix = fractionDigits.isEmpty ? tail : String(tail.dropFirst(fractionDigits.count + 1))
        let fraction = fractionDigits.isEmpty ? 0 : (Double("0." + fractionDigits) ?? 0)
        guard let whole = formatter.date(from: String(text.prefix(19)) + suffix),
              whole.addingTimeInterval(fraction) < upperBound else { throw OmniError.input("Invalid timestamp '\(text)'.") }
        return whole.addingTimeInterval(fraction)
    }
}
