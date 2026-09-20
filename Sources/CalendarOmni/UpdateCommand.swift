import ArgumentParser
import Foundation
import Darwin

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update non-recurring events from edited CalendarOmni JSON.")
    @Option(name: .long, help: "JSON file path, or - for piped stdin.") var input: String
    @Option(name: .long, help: "Output format: json or semicolon csv.") var format: OutputFormat = .json

    @MainActor mutating func run() async throws {
        let document = try validateInput {
            let data: Data
            if input == "-" {
                guard isatty(STDIN_FILENO) == 0 else { throw OmniError.input("--input - requires piped JSON.") }
                data = try FileHandle.standardInput.readToEnd() ?? Data()
            } else { data = try Data(contentsOf: URL(fileURLWithPath: input)) }
            return try UpdateDocument.parse(data)
        }
        try await execute {
            if document.patches.isEmpty {
                try OutputWriter.write(EventOutput(command: "update", zone: document.zone, records: []), format: format)
                return
            }
            let service = CalendarService(zone: document.zone)
            try await service.authorize()
            let result = try service.update(document)
            try OutputWriter.write(EventOutput(command: "update", zone: document.zone, records: result.records), format: format, saved: result.saved)
        }
    }
}
