import Foundation
import Combine
import DSHKit

/// 把「工具审批」从 Agent 的异步闭包桥接到 SwiftUI。
@MainActor
final class ApprovalBroker: ObservableObject {
    @Published private(set) var pending: ApprovalRequest?
    private var continuation: CheckedContinuation<Bool, Never>?

    func request(_ request: ApprovalRequest) async -> Bool {
        // 同一时刻只允许一个审批；若已有，直接拒绝，避免并发弹窗。
        guard pending == nil else { return false }
        pending = request
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ allowed: Bool) {
        pending = nil
        continuation?.resume(returning: allowed)
        continuation = nil
    }
}
