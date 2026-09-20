import XCTest
import Foundation
import EventKit

final class CalendarOmniTests: XCTestCase {
    private var dates: DateParsing { DateParsing(zone: TimeZone(identifier: "Europe/Copenhagen")!) }
    private var ref: EventReference { EventReference(eventId: "event-1", calendarId: "calendar-1", isRecurring: false, occurrenceDate: nil) }
    private var record: EventRecord {
        EventRecord(reference: ref, title: "Møde; \"rapport\"", start: "2026-09-21T09:00:00+02:00", end: "2026-09-21T10:00:00+02:00", location: nil,
                    attendees: [Attendee(name: nil, url: "mailto:person@example.org")], notes: "First line\nSecond line")
    }
    private func input(_ records: [[String: Any]], fields: [String] = EventField.allCases.map(\.rawValue)) throws -> UpdateDocument {
        try UpdateDocument.parse(JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "command": "extract", "timeZone": "Europe/Copenhagen", "fields": fields, "events": records]))
    }
    private var referenceObject: [String: Any] {
        ["eventId": "event-1", "calendarId": "calendar-1", "isRecurring": false, "occurrenceDate": NSNull()]
    }
    private func original() throws -> EditableValues {
        EditableValues(title: "Original", start: try DateParsing.timestamp("2026-09-21T09:00:00+02:00"),
            end: try DateParsing.timestamp("2026-09-21T10:00:00+02:00"), isAllDay: false, location: "Room 2", notes: "Keep me", attendees: [])
    }

    func testStrictCivilDates() throws {
        XCTAssertEqual(try dates.dayString(dates.day("2024-02-29")), "2024-02-29")
        for invalid in ["2025-02-29", "2026-02-30", "2026-13-01", "2026-9-01", "0000-01-01", "2026-01-01x"] {
            XCTAssertThrowsError(try dates.day(invalid), invalid)
        }
    }

    func testDSTRangesUseCivilDays() throws {
        let spring = try dates.range(from: "2026-03-29", to: "2026-03-29")
        let fall = try dates.range(from: "2026-10-25", to: "2026-10-25")
        XCTAssertEqual(spring.1.timeIntervalSince(spring.0), 23 * 3600)
        XCTAssertEqual(fall.1.timeIntervalSince(fall.0), 25 * 3600)
        XCTAssertThrowsError(try dates.range(from: "2026-09-22", to: "2026-09-21"))
    }

    func testDSTAmbiguityAndMissingTimes() throws {
        XCTAssertThrowsError(try dates.localTime(day: "2026-03-29", clock: "02:30"))
        XCTAssertThrowsError(try dates.localTime(day: "2026-10-25", clock: "02:30"))
        let valid = try dates.localTime(day: "2026-03-29", clock: "03:30")
        XCTAssertTrue(dates.timestamp(valid).contains("03:30:00"))
        XCTAssertThrowsError(try dates.localTime(day: "2026-09-21", clock: "24:00"))
    }

    func testCreationDurationAndOvernight() throws {
        let (start, end) = try dates.creationDates(date: "2026-09-21", start: "23:30", end: nil, duration: "1h30m")
        XCTAssertEqual(end.timeIntervalSince(start), 5400)
        XCTAssertEqual(dates.dayString(end), "2026-09-22")
        XCTAssertThrowsError(try dates.creationDates(date: "2026-09-21", start: "23:30", end: "01:00", duration: nil))
        XCTAssertThrowsError(try dates.creationDates(date: "2026-09-21", start: "9:00", end: "10:00", duration: "1h"))
        for invalid in ["0m", "-1h", "", "h", "1h30", "999999999999999999999999999h"] {
            XCTAssertThrowsError(try DateParsing.durationMinutes(invalid))
        }
        XCTAssertEqual(try DateParsing.durationMinutes("2H5M"), 125)
    }

    func testRFC3339Strictness() throws {
        XCTAssertEqual(try DateParsing.timestamp("2026-09-21T09:00:00+02:00"), try DateParsing.timestamp("2026-09-21T07:00:00Z"))
        for invalid in ["2026-02-30T09:00:00Z", "2026-09-21T24:00:00Z", "2026-09-21T09:00:00", "2026-09-21T09:00:00-00:00", "2026-09-21T09:00:00+02:99"] {
            XCTAssertThrowsError(try DateParsing.timestamp(invalid), invalid)
        }
        let precise = try DateParsing.timestamp("2026-09-21T09:00:00.123456+02:00")
        XCTAssertEqual(try DateParsing.timestamp(dates.timestamp(precise)), precise)
    }

    func testLongRangeWindowsAreContiguous() throws {
        let (start, end) = try dates.range(from: "2010-01-01", to: "2026-09-20")
        let windows = dates.windows(from: start, to: end)
        XCTAssertEqual(windows.count, 17)
        XCTAssertEqual(windows.first!.0, start); XCTAssertEqual(windows.last!.1, end)
        for i in 1..<windows.count { XCTAssertEqual(windows[i - 1].1, windows[i].0) }
    }

    func testFieldSelection() throws {
        XCTAssertEqual(try EventField.selection("notes, title"), [.notes, .title])
        XCTAssertEqual(try EventField.selection("all"), EventField.allCases)
        for invalid in ["none", "", "title,title", "all,title", "title,", "Title"] { XCTAssertThrowsError(try EventField.selection(invalid)) }
    }

    func testJSONProjectionAlwaysRetainsReference() throws {
        let output = EventOutput(command: "extract", zone: dates.zone, fields: [.notes, .location], records: [record])
        let object = try JSONSerialization.jsonObject(with: OutputWriter.data(output, format: .json)) as! [String: Any]
        let event = (object["events"] as! [[String: Any]])[0]
        XCTAssertEqual(Set(event.keys), ["_ref", "notes", "location"])
        XCTAssertTrue(event["location"] is NSNull)
        XCTAssertTrue((event["_ref"] as! [String: Any])["occurrenceDate"] is NSNull)
    }

    func testCSVQuotingAndMultiline() throws {
        let output = EventOutput(command: "extract", zone: dates.zone, fields: [.title, .notes, .attendees], records: [record])
        let csv = String(decoding: try OutputWriter.data(output, format: .csv), as: UTF8.self)
        XCTAssertTrue(csv.hasPrefix("title;notes;attendees\r\n"))
        XCTAssertTrue(csv.contains("\"Møde; \"\"rapport\"\"\""))
        XCTAssertTrue(csv.contains("\"First line\nSecond line\""))
        XCTAssertTrue(csv.contains("\"\"name\"\":null"))
        XCTAssertEqual(OutputWriter.csvCell("plain,comma"), "plain,comma")
    }

    func testEmptyOutputAndUpdate() throws {
        let output = EventOutput(command: "extract", zone: dates.zone, fields: [.title], records: [])
        XCTAssertEqual(String(decoding: try OutputWriter.data(output, format: .csv), as: UTF8.self), "title\r\n")
        XCTAssertEqual(try input([]).patches.count, 0)
    }

    func testRoundTripEverySelection() throws {
        let fields = EventField.allCases
        for mask in 1..<(1 << fields.count) {
            let selected = fields.enumerated().compactMap { (mask & (1 << $0.offset)) != 0 ? $0.element : nil }
            let output = EventOutput(command: "extract", zone: dates.zone, fields: selected, records: [record])
            let parsed = try UpdateDocument.parse(OutputWriter.data(output, format: .json))
            XCTAssertEqual(parsed.patches.count, 1)
        }
    }

    func testPatchPreservesOmittedAndClearsNull() throws {
        let document = try input([["_ref": referenceObject, "location": NSNull(), "title": "Revised"]])
        let before = try original(), after = try document.patches[0].merged(with: before, dates: dates)
        XCTAssertNil(after.location); XCTAssertEqual(after.title, "Revised")
        XCTAssertEqual(after.notes, before.notes); XCTAssertEqual(after.start, before.start); XCTAssertEqual(after.end, before.end)
    }

    func testInputRejectsMalformedAndDuplicateTargets() throws {
        let good: [String: Any] = ["_ref": referenceObject, "title": "New"]
        XCTAssertThrowsError(try input([good, good]))
        XCTAssertThrowsError(try input([["_ref": referenceObject]]))
        XCTAssertThrowsError(try input([["title": "Missing identity"]]))
        XCTAssertThrowsError(try input([["_ref": referenceObject, "unknown": "x"]]))
        XCTAssertThrowsError(try input([good], fields: ["notes"]))
        for key in ["title", "start", "end"] { XCTAssertThrowsError(try input([["_ref": referenceObject, key: NSNull()]])) }
        var recurring = referenceObject; recurring["isRecurring"] = true
        XCTAssertThrowsError(try input([["_ref": recurring, "title": "x"]]))
        var noID = referenceObject; noID["eventId"] = NSNull()
        XCTAssertThrowsError(try input([["_ref": noID, "title": "x"]]))
        XCTAssertThrowsError(try UpdateDocument.parse(Data([0xff])))
    }

    func testUpdatedDatesValidateCombinedEvent() throws {
        let bad = try input([["_ref": referenceObject, "end": "2026-09-21T08:00:00+02:00"]])
        XCTAssertThrowsError(try bad.patches[0].merged(with: original(), dates: dates))
        let conversion = try input([["_ref": referenceObject, "start": "2026-09-21"]])
        XCTAssertThrowsError(try conversion.patches[0].merged(with: original(), dates: dates))
        var allDay = try original(); allDay.isAllDay = true
        allDay.start = try dates.day("2026-09-21"); allDay.end = try dates.day("2026-09-22")
        let patch = try input([["_ref": referenceObject, "end": "2026-09-23"]])
        XCTAssertEqual(try patch.patches[0].merged(with: allDay, dates: dates).end, try dates.day("2026-09-23"))
    }

    func testAttendeesCannotBeChanged() throws {
        let changed = try input([["_ref": referenceObject, "attendees": [["name": "A", "url": "mailto:a@example.org"]]]])
        XCTAssertThrowsError(try changed.patches[0].merged(with: original(), dates: dates))
        let unchanged = try input([["_ref": referenceObject, "attendees": []]])
        XCTAssertEqual(try unchanged.patches[0].merged(with: original(), dates: dates), try original())
    }

    @MainActor func testOverlapBoundaries() {
        func d(_ n: Double) -> Date { Date(timeIntervalSince1970: n) }
        XCTAssertTrue(CalendarService.overlaps(start: d(0), end: d(15), from: d(10), to: d(20)))
        XCTAssertFalse(CalendarService.overlaps(start: d(0), end: d(10), from: d(10), to: d(20)))
        XCTAssertFalse(CalendarService.overlaps(start: d(20), end: d(25), from: d(10), to: d(20)))
        XCTAssertTrue(CalendarService.overlaps(start: d(10), end: d(10), from: d(10), to: d(20)))
        XCTAssertFalse(CalendarService.overlaps(start: d(20), end: d(20), from: d(10), to: d(20)))
    }

    @MainActor func testUnsavedEventRecurrenceClassification() {
        // In-memory only; no authorization, calendar assignment, or save.
        let event = EKEvent(eventStore: EKEventStore())
        event.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        event.endDate = event.startDate.addingTimeInterval(3600)
        XCTAssertFalse(CalendarService.isRecurring(event))
        event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
        XCTAssertTrue(CalendarService.isRecurring(event))
    }
}
