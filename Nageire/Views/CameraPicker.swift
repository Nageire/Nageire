#if os(iOS)
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The system's camera, which hands over the photo taken.
struct CameraPicker: UIViewControllerRepresentable {
    /// The photo, and the metadata the camera gives it, the time it was taken and the camera, as a property list:
    /// a dictionary of `Any` cannot cross to the encode off the main actor, and its bytes can.
    let onPhoto: (UIImage, Data) -> Void

    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// The photo as a JPEG at full quality with the camera's metadata, off the main actor: the app reduces and encodes it
    /// again at the size Settings gives. `jpegData` would drop the metadata, and with it the time the photo was taken.
    @concurrent
    nonisolated static func jpeg(of photo: UIImage, metadata: Data) async throws -> Data {
        guard let image = photo.cgImage else { throw PhotoError.unreadable }
        var properties = (try? PropertyListSerialization.propertyList(from: metadata, format: nil)) as? [String: Any] ?? [:]
        properties[kCGImagePropertyOrientation as String] = CGImagePropertyOrientation(photo.imageOrientation).rawValue
        properties[kCGImageDestinationLossyCompressionQuality as String] = 1.0
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoError.unwritable
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.unwritable }
        return output as Data
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(picker: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let picker: CameraPicker

        init(picker: CameraPicker) {
            self.picker = picker
        }

        func imagePickerController(_ controller: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let photo = info[.originalImage] as? UIImage {
                let metadata = (info[.mediaMetadata] as? [String: Any]).flatMap { try? PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }
                picker.onPhoto(photo, metadata ?? Data())
            }
            picker.dismiss()
        }

        func imagePickerControllerDidCancel(_ controller: UIImagePickerController) {
            picker.dismiss()
        }
    }
}
private nonisolated extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        self = switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
#else
/// There is no camera to take a photo with on macOS.
enum CameraPicker {
    static let isAvailable = false
}
#endif
