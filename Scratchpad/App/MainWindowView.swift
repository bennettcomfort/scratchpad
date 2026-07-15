import SwiftUI

struct MainWindowView: View {
    @Environment(ApplicationModel.self) private var model

    var body: some View {
        EditorHost(document: model.document)
            .id(model.document.id)
            .frame(minWidth: 480, minHeight: 320)
    }
}
