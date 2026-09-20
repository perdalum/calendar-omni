import Foundation
import EventKit

// NotificationCenter can deliver from any queue. This counter alone crosses queues.
private final class StoreGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    func increment() { lock.lock(); defer { lock.unlock() }; generation += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return generation }
}

@MainActor
final class CalendarService {
    let store: EKEventStore
    let dates: DateParsing

    init(zone: TimeZone) {
        NSTimeZone.default = zone
        dates = DateParsing(zone: zone)
        store = EKEventStore()
    }

    func authorize() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return }
        if status == .denied || status == .restricted {
            throw OmniError.operation("Calendar access is denied or restricted. Enable Calendar full access for the launching application in System Settings > Privacy & Security > Calendars, then retry.")
        }
        let granted: Bool
        do { granted = try await store.requestFullAccessToEvents() }
        catch { throw OmniError.operation("Calendar authorization failed: \(error.localizedDescription)") }
        guard granted else { throw OmniError.operation("Full Calendar access was not granted. Run interactively and allow access before unattended use.") }
    }

    func calendar(name: String?, id: String?) throws -> EKCalendar {
        let calendars = store.calendars(for: .event)
        let matches = calendars.filter { id != nil ? $0.calendarIdentifier == id : $0.title == name }
        guard matches.count == 1 else {
            let listed = (matches.isEmpty ? calendars : matches).sorted { $0.title < $1.title }.map {
                "  \($0.title) [\($0.source.title)] — \($0.calendarIdentifier)"
            }.joined(separator: "\n")
            throw OmniError.operation("Calendar selection matched \(matches.count) calendars. Use an exact name or --calendar-id.\n\(listed)")
        }
        return matches[0]
    }

    static func isRecurring(_ event: EKEvent) -> Bool {
        // occurrenceDate can equal startDate even on a newly created standalone event.
        // Rules and detached status establish membership; occurrenceDate only identifies it.
        event.hasRecurrenceRules || event.isDetached
    }

    static func overlaps(start: Date, end: Date, from: Date, to: Date) -> Bool {
        start == end ? (start >= from && start < to) : (start < to && end > from)
    }

    func extract(calendar: EKCalendar, from: Date, to: Date, includeRecurring: Bool,
                 filter: String?, regex: NSRegularExpression?) throws -> [EventRecord] {
        var events: [EKEvent] = []
        var seen = Set<OccurrenceKey>()
        for (start, end) in dates.windows(from: from, to: to) {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
            for event in store.events(matching: predicate) {
                guard let eventStart = event.startDate, let eventEnd = event.endDate,
                      Self.overlaps(start: eventStart, end: eventEnd, from: from, to: to),
                      includeRecurring || !Self.isRecurring(event) else { continue }
                let title = event.title ?? ""
                if let filter, title.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) == nil { continue }
                if let regex, regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) == nil { continue }
                if let id = event.eventIdentifier {
                    let key = OccurrenceKey(calendar: calendar.calendarIdentifier, event: id, start: eventStart, end: eventEnd)
                    guard seen.insert(key).inserted else { continue }
                }
                events.append(event)
            }
        }
        events.sort {
            ($0.startDate!, $0.endDate!, $0.calendar.calendarIdentifier, $0.eventIdentifier ?? "", $0.title ?? "") <
            ($1.startDate!, $1.endDate!, $1.calendar.calendarIdentifier, $1.eventIdentifier ?? "", $1.title ?? "")
        }
        return try events.map(record)
    }

    private struct OccurrenceKey: Hashable {
        let calendar: String
        let event: String
        let start: Date
        let end: Date
    }

    func create(calendar: EKCalendar, title: String, start: Date, end: Date, location: String?, notes: String?) throws -> EventRecord {
        guard calendar.allowsContentModifications else { throw OmniError.operation("Calendar '\(calendar.title)' is read-only.") }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar; event.title = title
        event.startDate = start; event.endDate = end; event.timeZone = dates.zone
        event.location = location; event.notes = notes
        do { try store.save(event, span: .thisEvent, commit: true) }
        catch { throw OmniError.operation("Event save failed; verify the calendar before retrying: \(error.localizedDescription)") }
        do { return try record(event) }
        catch { throw OmniError.operation("Event was saved but its result could not be read. Re-extract before retrying. \(error.localizedDescription)") }
    }

    func update(_ document: UpdateDocument) throws -> (records: [EventRecord], saved: Bool) {
        let generation = StoreGeneration()
        let observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in generation.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        let initialGeneration = generation.value
        var prepared: [(EKEvent, EditableValues, Bool)] = []
        // Complete validation before modifying any fetched event.
        for patch in document.patches {
            guard let id = patch.reference.eventId, let event = store.event(withIdentifier: id) else {
                throw OmniError.operation("Event ID '\(patch.reference.eventId ?? "null")' is no longer available. Extract again; no replacement was created.")
            }
            guard event.calendar.calendarIdentifier == patch.reference.calendarId else { throw OmniError.operation("Calendar changed for '\(id)'; extract again.") }
            guard event.calendar.allowsContentModifications else { throw OmniError.operation("Calendar for '\(id)' is read-only.") }
            guard !Self.isRecurring(event) else { throw OmniError.operation("Event '\(id)' belongs to a recurring series; updates are not supported in 1.0.0.") }
            let original = try values(event)
            let merged = try patch.merged(with: original, dates: dates)
            prepared.append((event, merged, merged != original))
        }
        guard generation.value == initialGeneration else { throw OmniError.operation("Calendar store changed during preparation; extract again before retrying.") }
        var saved = false
        do {
            for (event, value, changed) in prepared where changed {
                // Assign only changed values, preserving floating/time-zone semantics and other properties.
                if event.title != value.title { event.title = value.title }
                if event.startDate != value.start { event.startDate = value.start }
                if event.endDate != value.end { event.endDate = value.end }
                if event.location != value.location { event.location = value.location }
                if event.notes != value.notes { event.notes = value.notes }
                try store.save(event, span: .thisEvent, commit: false)
            }
            guard generation.value == initialGeneration else { throw OmniError.operation("Calendar store changed before commit; extract again.") }
        } catch {
            store.reset()
            throw OmniError.operation("Update was not committed: \(error.localizedDescription)")
        }
        if prepared.contains(where: { $0.2 }) {
            do { try store.commit(); saved = true }
            catch { store.reset(); throw OmniError.operation("Commit failed; outcome may be uncertain. Re-extract before retrying: \(error.localizedDescription)") }
        }
        do { return (try prepared.map { try record($0.0) }, saved) }
        catch { throw OmniError.operation("Update completed but result mapping failed. Re-extract before retrying: \(error.localizedDescription)") }
    }

    private func attendees(_ event: EKEvent) -> [Attendee] {
        Attendee.sorted((event.attendees ?? []).map { Attendee(name: $0.name, url: $0.url.absoluteString) })
    }

    private func values(_ event: EKEvent) throws -> EditableValues {
        guard let start = event.startDate, let end = event.endDate else { throw OmniError.operation("EventKit returned an event without start or end.") }
        return EditableValues(title: event.title ?? "", start: start, end: end, isAllDay: event.isAllDay,
                              location: event.location, notes: event.notes, attendees: attendees(event))
    }

    private func record(_ event: EKEvent) throws -> EventRecord {
        let v = try values(event)
        let recurring = Self.isRecurring(event)
        return EventRecord(reference: EventReference(eventId: event.eventIdentifier, calendarId: event.calendar.calendarIdentifier,
                isRecurring: recurring, occurrenceDate: recurring ? event.occurrenceDate.map(dates.timestamp) : nil),
            title: v.title, start: event.isAllDay ? dates.dayString(v.start) : dates.timestamp(v.start),
            end: event.isAllDay ? dates.dayString(v.end) : dates.timestamp(v.end),
            location: v.location, attendees: v.attendees, notes: v.notes)
    }
}
