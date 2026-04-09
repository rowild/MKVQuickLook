import XCTest

final class BundleMetadataTests: XCTestCase {
    func testAppExportsMediaTypesAndClaimsDocumentOwnership() throws {
        let info = try appInfoDictionary()

        let exportedTypes = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.mkv" }))
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.webm" }))
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.ogg-video" }))
        XCTAssertTrue(exportedTypes.contains(where: { ($0["UTTypeIdentifier"] as? String) == "com.robertwildling.mkvquicklook.avi" }))

        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        XCTAssertTrue(documentTypes.contains(where: {
            ($0["CFBundleTypeRole"] as? String) == "Viewer"
                && ($0["LSHandlerRank"] as? String) == "Owner"
                && (($0["LSItemContentTypes"] as? [String])?.contains("com.robertwildling.mkvquicklook.mkv") == true)
        }))
    }

    func testExtensionSupportsCustomMediaTypes() throws {
        let info = try extensionInfoDictionary()
        let extensionDictionary = try XCTUnwrap(info["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionDictionary["NSExtensionAttributes"] as? [String: Any])
        let supportedTypes = try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String])

        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.mkv"))
        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.webm"))
        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.ogg-video"))
        XCTAssertTrue(supportedTypes.contains("com.robertwildling.mkvquicklook.avi"))
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
