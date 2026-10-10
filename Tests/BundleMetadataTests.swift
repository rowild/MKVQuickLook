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
