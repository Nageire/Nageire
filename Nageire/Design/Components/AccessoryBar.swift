import SwiftUI

/// The bar above the keyboard on iOS: the attachments, the marks of the Markdown, then the key that lowers the keyboard.
/// The design's file button arrives with the file picker.
struct AccessoryBar: View {
    let perform: (EditorCommand) -> Void
    let hideKeyboard: () -> Void
    /// Nil where the editor adds no photo, and the button is absent.
    var addPhotos: (() -> Void)?
    /// Nil where there is no camera or the editor adds no photo.
    var takePhoto: (() -> Void)?

    var canAddPhotos: Bool { addPhotos != nil }
    var canTakePhoto: Bool { takePhoto != nil }

    var body: some View {
        HStack(spacing: 0) {
            if let addPhotos {
                key("Add Photos", systemImage: "photo", action: addPhotos)
                if let takePhoto {
                    key("Take Photo", systemImage: "camera", action: takePhoto)
                }
                Hairline(axis: .vertical)
                    .frame(height: 22)
            }
            key("Heading", systemImage: "number") { perform(.heading) }
            key("List", systemImage: "list.bullet") { perform(.list) }
            key("Checklist", systemImage: "checklist") { perform(.checklist) }
            key("Bold", systemImage: "bold") { perform(.bold) }
            key("Add Link", systemImage: "link") { perform(.link) }
            Spacer(minLength: 0)
            Hairline(axis: .vertical)
                .frame(height: 22)
            key("Hide Keyboard", systemImage: "keyboard.chevron.compact.down", action: hideKeyboard)
        }
        .padding(.horizontal, 8)
        .frame(height: Spacing.control)
        .background(.paperRaised)
        .overlay(alignment: .top) { Hairline() }
    }

    private func key(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 20))
            .foregroundStyle(.ink)
            .frame(width: 40, height: Spacing.control)
    }
}

#Preview {
    AccessoryBar(perform: { _ in }, hideKeyboard: {}, addPhotos: {}, takePhoto: {})
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(.paper)
}
