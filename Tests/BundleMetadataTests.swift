import UniformTypeIdentifiers
import XCTest

final class BundleMetadataTests: XCTestCase {
    func testAppExportsMediaTypesAndClaimsDocumentOwnership() throws {
        let info = try appInfoDictionary()

        let exportedTypes = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.mkv" }))
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.webm" }))
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.ogg-video" }))
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.avi" }))
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.opus" }))

        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        XCTAssertTrue(documentTypes.contains(where: {
            ($0["CFBundleTypeRole"] as? String) == "Viewer"
                && ($0["LSHandlerRank"] as? String) == "Owner"
                && (($0["LSItemContentTypes"] as? [String])?.contains("com.robertwildling.mkvquicklook.mkv") == true)
        }))
        XCTAssertTrue(documentTypes.contains(where: {
            ($0["CFBundleTypeRole"] as? String) == "Viewer"
                && ($0["LSHandlerRank"] as? String) == "Owner"
                && (($0["LSItemContentTypes"] as? [String])?.contains("com.robertwildling.mkvquicklook.opus") == true)
        }))
    }

    func testExtensionSupportsCustomMediaTypes() throws {
        let supportedTypes = try extensionSupportedContentTypes()

        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.mkv"))
        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.webm"))
        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.ogg-video"))
        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.avi"))
        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.opus"))
        XCTAssertTrue(supportedTypes.contains("org.xiph.opus"))
    }

    // Quick Look routes a file by the type identifier macOS resolves for it. Other
    // installed apps (VLC, Chromium-based browsers, ...) can declare their own
    // identifiers for the same extensions, and theirs may win over ours. So the
    // extension must cover whatever identifier this Mac actually resolves.
    func testExtensionCoversTypesResolvedOnThisMacForAdvertisedExtensions() throws {
        let supportedTypes = try extensionSupportedContentTypes().compactMap { UTType($0) }

        for fileExtension in ["mkv", "webm", "ogg", "ogv", "opus"] {
            guard let resolvedType = UTType(filenameExtension: fileExtension), !resolvedType.isDynamic else {
                // No app on this Mac declares the extension; nothing to route against.
                continue
            }

            XCTAssertTrue(
                supportedTypes.contains { resolvedType.conforms(to: $0) },
                ".\(fileExtension) resolves to \(resolvedType.identifier) on this Mac, which QLSupportedContentTypes does not cover"
            )
        }
    }

    // VLCKit is LGPL-2.1. The distributed app must carry the license text.
    func testBuiltAppShipsVLCKitLicense() throws {
        let appURL = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("MKVQuickLook.app")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appURL.path),
            "Expected the built app next to the test bundle. Build and test with the MKVQuickLook scheme."
        )

        let licenseURL = appURL.appendingPathComponent("Contents/Resources/VLCKit-COPYING.txt")
        let licenseText = try String(contentsOf: licenseURL, encoding: .utf8)

        XCTAssertTrue(licenseText.contains("GNU LESSER GENERAL PUBLIC LICENSE"))
    }

    // VLCKit is about 79 MB. The app embeds it once; the extension's reference is
    // rewritten after linking to load the app's copy (see project.yml). Together with
    // the load-path test below this pins down "one copy, and everything can load it".
    func testBuiltAppEmbedsVLCKitOnce() throws {
        let appURL = try builtAppURL()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: nil))
        let copies = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "VLCKit.framework" }
            .map { $0.path.replacingOccurrences(of: appURL.path + "/", with: "") }

        XCTAssertEqual(copies, ["Contents/Frameworks/VLCKit.framework"])
    }

    // Resolves every recorded VLCKit load path of the app and of the extension the way
    // dyld does (@loader_path, @executable_path, @rpath + LC_RPATH). VLCKit's install
    // name is @loader_path/../Frameworks/..., so each binary needs VLCKit in the
    // Frameworks folder next to it; a wrong bundle layout crashes the extension at
    // launch ("Library not loaded") long before any test or log line could notice.
    func testEveryBinaryCanResolveItsVLCKitLoadPath() throws {
        let appURL = try builtAppURL()
        let binaryDirectories = [
            appURL.appendingPathComponent("Contents/MacOS"),
            appURL.appendingPathComponent("Contents/PlugIns/MKVQuickLookPreviewExtension.appex/Contents/MacOS"),
        ]

        for directory in binaryDirectories {
            let images = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { !$0.hasPrefix("__") }
                .map { directory.appendingPathComponent($0) }
            let runpaths = try images.flatMap { try loadCommandValues(of: $0, command: "LC_RPATH", key: "path") }
                .map { $0.replacingOccurrences(of: "@executable_path", with: directory.path)
                    .replacingOccurrences(of: "@loader_path", with: directory.path) }
            var checkedReferences = 0

            for image in images {
                for reference in try loadCommandValues(of: image, command: "LC_LOAD_DYLIB", key: "name") where reference.contains("VLCKit") {
                    checkedReferences += 1
                    let candidates: [String]
                    if reference.hasPrefix("@rpath/") {
                        let suffix = reference.dropFirst("@rpath/".count)
                        candidates = runpaths.map { "\($0)/\(suffix)" }
                    } else {
                        candidates = [reference
                            .replacingOccurrences(of: "@loader_path", with: directory.path)
                            .replacingOccurrences(of: "@executable_path", with: directory.path)]
                    }
                    XCTAssertTrue(
                        candidates.contains { FileManager.default.fileExists(atPath: $0) },
                        "\(image.lastPathComponent) cannot load \(reference); tried \(candidates)"
                    )
                }
            }
            XCTAssertGreaterThan(checkedReferences, 0, "No VLCKit reference found in \(directory.path)")
        }
    }

    private func builtAppURL() throws -> URL {
        let appURL = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("MKVQuickLook.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            struct MissingBuiltApp: LocalizedError {
                var errorDescription: String? {
                    "Expected the built app next to the test bundle. Build and test with the MKVQuickLook scheme."
                }
            }
            throw MissingBuiltApp()
        }
        return appURL
    }

    // Reads the `key` value (for example `path` or `name`) of one Mach-O load command
    // type with otool.
    private func loadCommandValues(of binary: URL, command: String, key: String) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        process.arguments = ["-l", binary.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        var paths: [String] = []
        var inCommand = false
        for line in output.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("cmd ") {
                inCommand = line == "cmd \(command)"
            } else if inCommand, line.hasPrefix("\(key) ") {
                // "path @executable_path/../Frameworks (offset 12)"
                let value = line.dropFirst(key.count + 1)
                paths.append(String(value.split(separator: " (offset").first ?? value[...]))
            }
        }
        return paths
    }

    private func extensionSupportedContentTypes() throws -> [String] {
        let info = try extensionInfoDictionary()
        let extensionDictionary = try XCTUnwrap(info["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionDictionary["NSExtensionAttributes"] as? [String: Any])
        return try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String])
    }

    private func appInfoDictionary() throws -> [String: Any] {
        try infoDictionary(at: "MKVQuickLookApp/Resources/Info.plist")
    }

    private func extensionInfoDictionary() throws -> [String: Any] {
        try infoDictionary(at: "MKVQuickLookPreviewExtension/Resources/Info.plist")
    }

    private func infoDictionary(at relativePath: String) throws -> [String: Any] {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = rootURL.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: plistURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(propertyList as? [String: Any])
    }
}
