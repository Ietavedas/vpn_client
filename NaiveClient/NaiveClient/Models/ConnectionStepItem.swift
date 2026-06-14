import Foundation

enum ConnectionStepStatus: Equatable {
    case pending
    case running
    case success
    case failed
}

struct ConnectionStepItem: Identifiable, Equatable {
    let id: String
    let title: String
    var status: ConnectionStepStatus = .pending
    var detail: String?
}
