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

    func testMissingKeysInOlderPayloadFail_gracefully() {
        // A partial payload must not crash; it falls back to defaults.
        let d = freshDefaults()
        d.set(Data("{\"version\":1}".utf8), forKey: SettingsStore.defaultsKey)
        XCTAssertEqual(SettingsStore(defaults: d).settings, .default)
    }
}
