import Foundation

enum JSONValue: Decodable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func object() throws -> [String: JSONValue] {
        guard case .object(let value) = self else { throw OmniError.input("Expected a JSON object.") }; return value
    }
    func string() throws -> String {
        guard case .string(let value) = self else { throw OmniError.input("Expected a JSON string, not null or another type.") }; return value
    }
    func array() throws -> [JSONValue] {
        guard case .array(let value) = self else { throw OmniError.input("Expected a JSON array.") }; return value
    }
}

enum Patch<Value: Equatable & Sendable>: Equatable, Sendable {
    case unchanged, value(Value)
    func applied(to original: Value) -> Value { if case .value(let value) = self { value } else { original } }
}

struct EditableValues: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var attendees: [Attendee]
}

struct EventPatch: Sendable {
    let reference: EventReference
    let title: Patch<String>
    let start: Patch<String>
    let end: Patch<String>
    let location: Patch<String?>
    let notes: Patch<String?>
    let attendees: Patch<[Attendee]>

    func merged(with original: EditableValues, dates: DateParsing) throws -> EditableValues {
        var result = original
        result.title = title.applied(to: original.title)
        result.location = location.applied(to: original.location)
        result.notes = notes.applied(to: original.notes)
        func mergeDate(_ patch: Patch<String>, original: Date) throws -> Date {
            guard case .value(let text) = patch else { return original }
            if originalIsAllDay {
                return try dates.day(text)
            }
            return try DateParsing.timestamp(text)
        }
        let originalIsAllDay = original.isAllDay
        result.start = try mergeDate(start, original: original.start)
        result.end = try mergeDate(end, original: original.end)
        guard !result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.end > result.start else { throw OmniError.input("Updated event needs a nonblank title and end after start.") }
        if case .value(let supplied) = attendees,
           Attendee.sorted(supplied) != Attendee.sorted(original.attendees) {
            throw OmniError.input("Attendees have changed for event '\(reference.eventId ?? "")'; EventKit cannot assign attendees.")
        }
        return result
    }
}

struct UpdateDocument: Sendable {
    let zone: TimeZone
    let patches: [EventPatch]

    static func parse(_ data: Data) throws -> UpdateDocument {
        guard String(data: data, encoding: .utf8) != nil else { throw OmniError.input("Input must be UTF-8 JSON.") }
        let root: [String: JSONValue]
        do { root = try JSONDecoder().decode(JSONValue.self, from: data).object() }
        catch let error as OmniError { throw error }
        catch { throw OmniError.input("Invalid JSON: \(error.localizedDescription)") }
        try keys(root, allowed: ["schemaVersion", "command", "timeZone", "fields", "events"], required: ["schemaVersion", "command", "timeZone", "fields", "events"])
        guard root["schemaVersion"] == .number(1), [.string("extract"), .string("create"), .string("update")].contains(root["command"]!) else {
            throw OmniError.input("Expected schemaVersion 1 and command extract, create, or update.")
        }
        let zone = try DateParsing.timeZone(root["timeZone"]!.string())
        let selectedNames = try root["fields"]!.array().map { try $0.string() }
        guard !selectedNames.isEmpty, selectedNames.allSatisfy({ EventField(rawValue: $0) != nil }),
              Set(selectedNames).count == selectedNames.count else { throw OmniError.input("Invalid or duplicate field selection in JSON.") }
        var seen = Set<String>()
        let patches = try root["events"]!.array().enumerated().map { index, value in
            do {
                let object = try value.object()
                try keys(object, allowed: Set(selectedNames).union(["_ref"]), required: ["_ref"])
                guard object.count > 1 else { throw OmniError.input("A record must include at least one content field.") }
                let ref = try object["_ref"]!.object()
                try keys(ref, allowed: ["eventId", "calendarId", "isRecurring", "occurrenceDate"], required: ["eventId", "calendarId", "isRecurring", "occurrenceDate"])
                let id = try ref["eventId"]!.string(), calID = try ref["calendarId"]!.string()
                guard !id.isEmpty, !calID.isEmpty else { throw OmniError.input("References must contain nonempty event and calendar IDs.") }
                guard ref["isRecurring"] == .bool(false), ref["occurrenceDate"] == .null else { throw OmniError.input("Updating recurring events is not supported in 0.0.1.") }
                guard seen.insert(id).inserted else { throw OmniError.input("Duplicate event ID '\(id)'.") }
                func text(_ key: String) throws -> Patch<String> {
                    guard let value = object[key] else { return .unchanged }
                    return .value(try value.string())
                }
                func nullableText(_ key: String) throws -> Patch<String?> {
                    guard let value = object[key] else { return .unchanged }
                    return .value(value == .null ? nil : try value.string())
                }
                let title = try text("title"), start = try text("start"), end = try text("end")
                if case .value(let title) = title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw OmniError.input("Title must not be blank.") }
                for field in [start, end] {
                    if case .value(let text) = field {
                        if text.count == 10 { _ = try DateParsing(zone: zone).day(text) }
                        else { _ = try DateParsing.timestamp(text) }
                    }
                }
                let attendees: Patch<[Attendee]>
                if let value = object["attendees"] {
                    attendees = .value(try value.array().map { value in
                        let item = try value.object()
                        try keys(item, allowed: ["name", "url"], required: ["name", "url"])
                        let url = try item["url"]!.string()
                        guard let parsed = URL(string: url), parsed.scheme != nil, !url.contains(where: { $0.isWhitespace }) else { throw OmniError.input("Attendee URL must be an absolute URI.") }
                        return Attendee(name: item["name"] == .null ? nil : try item["name"]!.string(), url: url)
                    })
                } else { attendees = .unchanged }
                return EventPatch(reference: EventReference(eventId: id, calendarId: calID, isRecurring: false, occurrenceDate: nil),
                    title: title, start: start, end: end, location: try nullableText("location"), notes: try nullableText("notes"), attendees: attendees)
            } catch { throw OmniError.input("events[\(index)]: \(error.localizedDescription)") }
        }
        return UpdateDocument(zone: zone, patches: patches)
    }

    private static func keys(_ object: [String: JSONValue], allowed: Set<String>, required: Set<String>) throws {
        let names = Set(object.keys)
        guard names.isSubset(of: allowed), required.isSubset(of: names) else {
            let unknown = names.subtracting(allowed).sorted().joined(separator: ", ")
            let missing = required.subtracting(names).sorted().joined(separator: ", ")
            throw OmniError.input("Invalid object keys. Unknown: [\(unknown)]. Missing: [\(missing)].")
        }
    }
}
