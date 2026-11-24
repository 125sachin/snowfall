import os

/// Structured local logging. Never logs window titles or other window metadata.
enum SnowfallLogger {
    static let app = Logger(subsystem: "com.xcode.snowfall", category: "app")
    static let overlay = Logger(subsystem: "com.xcode.snowfall", category: "overlay")
    static let render = Logger(subsystem: "com.xcode.snowfall", category: "render")
    static let tracking = Logger(subsystem: "com.xcode.snowfall", category: "tracking")
    static let sim = Logger(subsystem: "com.xcode.snowfall", category: "sim")
}
