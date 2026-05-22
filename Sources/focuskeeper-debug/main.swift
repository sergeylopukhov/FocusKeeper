import FocusBackend
import Foundation

let usage = """
Usage:
  focuskeeper-debug on
  focuskeeper-debug off
  focuskeeper-debug status
"""

let arguments = CommandLine.arguments.dropFirst()

guard let command = arguments.first, arguments.count == 1 else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}

let backend = FocusBackend()
let defaultModeIdentifier = "com.apple.focus.work"

do {
    switch command {
    case "on":
        try backend.enableFocus(modeIdentifier: defaultModeIdentifier)
        print("enabled")
    case "off":
        try backend.disableWorkFocus()
        print("disabled")
    case "status":
        print(try backend.getStatus(modeIdentifier: defaultModeIdentifier).rawValue)
    default:
        FileHandle.standardError.write(Data(usage.utf8))
        exit(2)
    }
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}
