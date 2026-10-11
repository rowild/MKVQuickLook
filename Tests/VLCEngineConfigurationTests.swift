import Foundation
import XCTest

// VLCKit 3.7.2 saves VLC's settings after every media release and input close. That
// save can freeze the process (see .plans/01-initial-plan.md, Pitfall #20). VLC skips
// the save when its settings file is read-only, so the engine gets its own read-only file.
final class VLCEngineConfigurationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VLCEngineConfigurationTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        // A read-only file in a writable folder can still be deleted.
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testSettingsFileIsCreatedEmptyAndReadOnly() throws {
        let file = directory.appendingPathComponent("folder/vlcrc")

        try VLCEngineConfiguration.prepareReadOnlySettingsFile(at: file)

        XCTAssertEqual(try Data(contentsOf: file), Data())
        XCTAssertEqual(try permissions(of: file), 0o444)
    }

    func testWritableSettingsFileIsMadeReadOnlyAndKeepsItsContent() throws {
        let file = directory.appendingPathComponent("vlcrc")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("[core]\n".utf8).write(to: file)

        try VLCEngineConfiguration.prepareReadOnlySettingsFile(at: file)

        XCTAssertEqual(try Data(contentsOf: file), Data("[core]\n".utf8))
        XCTAssertEqual(try permissions(of: file), 0o444)
    }

    func testApplyGivesVLCKitTheReadOnlySettingsFileAndKeepsItsDefaults() throws {
        let file = directory.appendingPathComponent("vlcrc")
        let suiteName = "MKVQuickLookTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        VLCEngineConfiguration.apply(settingsFile: file, defaults: defaults)

        let options = try XCTUnwrap(defaults.stringArray(forKey: "VLCParams"))
        XCTAssertTrue(options.contains("--config=\(file.path)"), "VLC would use VLC.app's settings file: \(options)")
        // Setting VLCParams replaces VLCKit's own defaults; the player relies on these.
        for option in ["--play-and-pause", "--vout=macosx", "--no-video-title-show"] {
            XCTAssertTrue(options.contains(option), "Missing VLCKit default \(option): \(options)")
        }
        XCTAssertFalse(options.contains("--no-volume-save"), "Without volume-save, VLC jumps to 100% after stop and play")
        XCTAssertEqual(try permissions(of: file), 0o444)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}
