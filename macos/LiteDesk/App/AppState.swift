import Foundation
import Combine

enum AppMode {
    case home
    case host
    case viewer
}

final class AppState: ObservableObject {
    @Published var mode: AppMode = .home
}
