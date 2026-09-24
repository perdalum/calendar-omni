import Foundation

enum EventField: String, CaseIterable, Codable, Sendable {
    case title, start, end, location, attendees, notes, duration

    static let contentFields: [EventField] = [.title, .start, .end, .location, .attendees, .notes]

    static func selection(_ text: String) throws -> [EventField] {
        if text == "all" { return contentFields }
        let names = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let fields = names.compactMap(Self.init(rawValue:))
        guard !fields.isEmpty, fields.count == names.count, Set(fields).count == fields.count else {
            throw OmniError.input("--fields must be 'all' or unique names from title,start,end,location,attendees,notes,duration.")
        }
        return fields
    }
}

struct EventReference: Codable, Equatable, Sendable {
    let eventId: String?
    let calendarId: String
    let isRecurring: Bool
    let occurrenceDate: String?

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eventId, forKey: .eventId); try c.encode(calendarId, forKey: .calendarId)
        try c.encode(isRecurring, forKey: .isRecurring); try c.encode(occurrenceDate, forKey: .occurrenceDate)
    }
}

struct Attendee: Codable, Equatable, Sendable {
    let name: String?
    let url: String
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(url, forKey: .url)
    }
    static func sorted(_ values: [Attendee]) -> [Attendee] {
        values.sorted { lhs, rhs in
            if lhs.url != rhs.url { return lhs.url < rhs.url }
            if (lhs.name == nil) != (rhs.name == nil) { return lhs.name == nil }
            return (lhs.name ?? "") < (rhs.name ?? "")
        }
    }
}

struct EventRecord: Sendable {
    let reference: EventReference
    let title: String
    let start: String
    let end: String
    let location: String?
    let attendees: [Attendee]
    let notes: String?

    func duration(in zone: TimeZone) throws -> Double {
        let dates = DateParsing(zone: zone)
        let first = try start.count == 10 ? dates.day(start) : DateParsing.timestamp(start)
        let last = try end.count == 10 ? dates.day(end) : DateParsing.timestamp(end)
        return last.timeIntervalSince(first) / 60
    }
}

struct SelectedEvent: Encodable {
    let record: EventRecord
    let fields: [EventField]
    let zone: TimeZone
    enum CodingKeys: String, CodingKey { case _ref, title, start, end, location, attendees, notes, duration }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(record.reference, forKey: ._ref)
        for field in fields {
            switch field {
            case .title: try c.encode(record.title, forKey: .title)
            case .start: try c.encode(record.start, forKey: .start)
            case .end: try c.encode(record.end, forKey: .end)
            case .location: try c.encode(record.location, forKey: .location)
            case .attendees: try c.encode(record.attendees, forKey: .attendees)
            case .notes: try c.encode(record.notes, forKey: .notes)
            case .duration: try c.encode(record.duration(in: zone), forKey: .duration)
            }
        }
    }
}

struct EventOutput: Encodable {
    let schemaVersion = 1
    let command: String
    let timeZone: String
    let fields: [EventField]
    let events: [SelectedEvent]

    init(command: String, zone: TimeZone, fields: [EventField] = EventField.contentFields, records: [EventRecord]) {
        self.command = command; timeZone = zone.identifier; self.fields = fields
        events = records.map { SelectedEvent(record: $0, fields: fields, zone: zone) }
    }
}
