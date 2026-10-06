#if DEBUG
import SwiftUI

extension View {
    /// Puts a sample model under a preview, with its defaults, so that the views read the sample's draft and settings and not the developer's.
    func sample(_ model: AppModel) -> some View {
        environment(model).defaultAppStorage(model.defaults)
    }
}
#endif
