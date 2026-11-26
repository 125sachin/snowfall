import XCTest
@testable import Snowfall

@MainActor
final class SettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "SnowfallTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaults() {
        let s = SnowfallSettings.default
        XCTAssertTrue(s.snowfallEnabled)
        XCTAssertEqual(s.particleDensity, 0.5)
        XCTAssertFalse(s.windowPhysicsEnabled)
        XCTAssertEqual(s.version, SnowfallSettings.currentVersion)
    }

    func testBackdropDefaultsToAutomatic() {
        XCTAssertEqual(SnowfallSettings.default.backdrop, .auto)
    }

    func testBackdropSurvivesRoundTripAndOldSettingsFallBack() throws {
        var s = SnowfallSettings.default
        s.backdrop = .light
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(SnowfallSettings.self, from: data).backdrop, .light)
        // Settings saved by an older version have no backdrop key; an unknown value is also tolerated.
        XCTAssertEqual(try JSONDecoder().decode(SnowfallSettings.self, from: Data("{}".utf8)).backdrop, .auto)
        XCTAssertEqual(try JSONDecoder().decode(SnowfallSettings.self, from: Data(#"{"backdrop":"neon"}"#.utf8)).backdrop, .auto)
    }

    func testValidationClamps() {
        var s = SnowfallSettings()
        s.particleDensity = 7
        s.windStrength = -3
        let v = s.validated()
        XCTAssertEqual(v.particleDensity, 1)
        XCTAssertEqual(v.windStrength, 0)
    }

    func testValidationHandlesNaN() {
        var s = SnowfallSettings()
        s.particleDensity = .nan
        XCTAssertEqual(s.validated().particleDensity, 0)
    }

    func testStoreClampsOnAssignment() {
        let store = SettingsStore(defaults: freshDefaults())
        store.settings.windStrength = 99
        XCTAssertEqual(store.settings.windStrength, 1)
    }

    func testPersistenceRoundTrip() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.settings.particleDensity = 0.8
        a.settings.targetFrameRate = .adaptive
        let b = SettingsStore(defaults: d)
        XCTAssertEqual(b.settings.particleDensity, 0.8)
        XCTAssertEqual(b.settings.targetFrameRate, .adaptive)
    }

    func testCorruptDataFallsBackToDefaults() {
        let d = freshDefaults()
        d.set(Data("garbage".utf8), forKey: SettingsStore.defaultsKey)
        XCTAssertEqual(SettingsStore(defaults: d).settings, .default)
    }

    func testOlderPayloadGetsDefaultsForNewKeys() {
        // A v1 payload lacking newer keys decodes with defaults and is migrated to the current version.
        let d = freshDefaults()
        d.set(Data("{\"version\":1}".utf8), forKey: SettingsStore.defaultsKey)
        XCTAssertEqual(SettingsStore(defaults: d).settings, .default)
    }
}

@MainActor
final class SettingsRangeTests: XCTestCase {
    func testNewFieldRangesClamp() {
        var s = SnowfallSettings()
        s.maxParticles = 99999; s.fallSpeed = 0; s.pointerRadius = 1; s.particleOpacity = 5
        s.disabledDisplays = ["b", "a", "b"]
        let v = s.validated()
        XCTAssertEqual(v.maxParticles, 3000)
        XCTAssertEqual(v.fallSpeed, 0.5)
        XCTAssertEqual(v.pointerRadius, 40)
        XCTAssertEqual(v.particleOpacity, 1)
        XCTAssertEqual(v.disabledDisplays, ["a", "b"])
    }

    func testV1PayloadKeepsKnownValues() throws {
        let json = #"{"version":1,"particleDensity":0.9,"windStrength":0.1}"#
        let s = try JSONDecoder().decode(SnowfallSettings.self, from: Data(json.utf8))
        XCTAssertEqual(SettingsStore.migrate(s).validated().particleDensity, 0.9)
        XCTAssertEqual(s.validated().version, SnowfallSettings.currentVersion)
    }

    func testSimulationSettingsMapping() {
        var ss = SimulationSettings(); ss.lowPower = true; ss.maxDepth = 1
        let c = ss.configuration(base: SimulationConfiguration(), densityScale: 1)
        XCTAssertEqual(c.densityScale, 0.5)
        XCTAssertEqual(c.displayMaxDepth, 60)
    }
}
