import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            StatsRow()
            HStack(alignment: .top, spacing: 14) {
                ExplorerCard()
                RecommendationsCard().frame(width: 390)
            }
        }
        .padding(18)
        .background(Color.page)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast?.id)
        .task {
            if model.phase == .idle { model.scan() }
        }
    }
}
