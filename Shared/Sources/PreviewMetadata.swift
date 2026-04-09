import AppKit
import Foundation

enum PreviewMediaKind: Equatable {
    case video
    case audioOnly
}

struct PreviewMetadata {
    let fileURL: URL
    let displayName: String
    let fileExtension: String
    let mediaKind: PreviewMediaKind
    let typeDescription: String
    let fileSizeDescription: String
    let modifiedDateDescription: String
    let icon: NSImage

    init(fileURL: URL) throws {
        let resourceValues = try fileURL.resourceValues(forKeys: [
            .nameKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .contentTypeKey
        ])

        self.fileURL = fileURL
        displayName = resourceValues.name ?? fileURL.lastPathComponent
        fileExtension = fileURL.pathExtension.lowercased()
        mediaKind = Self.mediaKind(for: fileExtension)
        typeDescription = Self.typeDescription(for: fileExtension, contentTypeDescription: resourceValues.contentType?.localizedDescription)
        fileSizeDescription = Self.fileSizeDescription(bytes: resourceValues.fileSize)
        modifiedDateDescription = Self.modifiedDateDescription(resourceValues.contentModificationDate)
        icon = NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    static func mediaKind(for fileExtension: String) -> PreviewMediaKind {
        switch fileExtension {
        case "opus":
            return .audioOnly
        default:
            return .video
        }
    }

    static func typeDescription(for fileExtension: String, contentTypeDescription: String?) -> String {
        if let contentTypeDescription, !contentTypeDescription.isEmpty {
            return contentTypeDescription
        }

        switch fileExtension {
        case "mkv":
            return "Matroska Video"
        case "webm":
            return "WebM Video"
        case "ogg", "ogv":
            return "Ogg Video"
        case "avi":
            return "AVI Video"
        case "opus":
            return "Opus Audio"
        default:
            return "Media File"
        }
    }

    static func fileSizeDescription(bytes: Int?) -> String {
        guard let bytes else {
            return "Unknown size"
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func modifiedDateDescription(_ date: Date?) -> String {
        guard let date else {
            return "Unknown modification date"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
