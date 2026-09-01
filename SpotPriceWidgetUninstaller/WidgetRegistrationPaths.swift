import Foundation

enum WidgetRegistrationPaths {
    static func extensionPaths(from pluginKitOutput: String) -> [String] {
        pluginKitOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard let last = fields.last else { return nil }
                let path = last.trimmingCharacters(in: .whitespacesAndNewlines)
                guard path.hasPrefix("/"), path.hasSuffix(".appex") else { return nil }
                return path
            }
    }
}
