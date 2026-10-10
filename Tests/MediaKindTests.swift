import AppKit
import CoreGraphics
import XCTest

final class MediaKindTests: XCTestCase {
    func testPreviewMetadataTreatsOpusAsAudio() {
        XCTAssertEqual(PreviewMetadata.mediaKind(for: "opus"), .audioOnly)
        XCTAssertEqual(
            PreviewMetadata.typeDescription(for: "opus", contentTypeDescription: nil),
            "Opus Audio"
        )
    }

    // Track dictionaries below mirror what VLCKit 3.7.2 reports after parsing the
    // local example-videos samples.
    func testTracksWithOnlyAudioAreAudioOnly() {
        let vorbisOgg: [Any] = [
            ["type": "audio", "codec": 1651666806, "rate": 44100] as [String: Any]
        ]

        XCTAssertEqual(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: vorbisOgg), .audioOnly)
    }

    func testTheoraTrackWithoutParsedSizeStillCountsAsVideo() {
        let theoraOgg: [Any] = [
            ["type": "video", "codec": 1868916852, "width": 0, "height": 0] as [String: Any],
            ["type": "audio", "codec": 1651666806, "rate": 44100] as [String: Any]
        ]

        XCTAssertEqual(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: theoraOgg), .video)
    }

    func testVideoWithAudioAndSubtitlesIsVideo() {
        let mkv: [Any] = [
            ["type": "video", "codec": 875967080, "width": 512, "height": 384] as [String: Any],
            ["type": "audio", "codec": 1630826605, "rate": 44100] as [String: Any],
            ["type": "text", "codec": 1952609651] as [String: Any]
        ]

        XCTAssertEqual(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: mkv), .video)
    }

    func testNoAudioOrVideoTracksGiveNoMediaKind() {
        XCTAssertNil(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: []))
        XCTAssertNil(VLCKitMediaPreviewPlayer.mediaKind(fromTracksInformation: [
            ["type": "text", "codec": 1952609651] as [String: Any]
        ]))
    }
}
