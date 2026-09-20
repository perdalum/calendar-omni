import Foundation
import Darwin

enum OutputFormat: String, CaseIterable { case json, csv }

enum OutputWriter {
    static func csvCell(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { [59, 34, 13, 10].contains($0.value) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func data(_ output: EventOutput, format: OutputFormat) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if format == .json {
            encoder.outputFormatting.insert(.prettyPrinted)
            var data = try encoder.encode(output); data.append(10); return data
        }
        var rows = [output.fields.map(\.rawValue).joined(separator: ";")]
        for event in output.events {
            let r = event.record
            let cells = try output.fields.map { field -> String in
                switch field {
                case .title: r.title
                case .start: r.start
                case .end: r.end
                case .location: r.location ?? ""
                case .notes: r.notes ?? ""
                case .attendees: String(decoding: try encoder.encode(r.attendees), as: UTF8.self)
                }
            }
            rows.append(cells.map(csvCell).joined(separator: ";"))
        }
        return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func write(_ output: EventOutput, format: OutputFormat, saved: Bool = false) throws {
        do { try FileHandle.standardOutput.write(contentsOf: data(output, format: format)) }
        catch {
            let prefix = saved ? "Calendar changes were committed, but output failed. Re-extract before retrying. " : "Output failed. "
            throw OmniError.operation(prefix + error.localizedDescription)
        }
    }
}
