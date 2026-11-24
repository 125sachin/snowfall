import os

/// Structured local logging. Never logs window titles or other window metadata.
enum SnowfallLogger {
    static let app = Logger(subsystem: "com.example.Snowfall", category: "app")
    static let overlay = Logger(subsystem: "com.example.Snowfall", category: "overlay")
    static let render = Logger(subsystem: "com.example.Snowfall", category: "render")
    static let tracking = Logger(subsystem: "com.example.Snowfall", category: "tracking")
    static let sim = Logger(subsystem: "com.example.Snowfall", category: "sim")
}
