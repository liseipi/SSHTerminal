import Foundation

enum SSHError: LocalizedError {
    case alreadyConnected
    case notConnected
    case connectionFailed
    case processCreationFailed
    case commandFailed(String)
    case invalidOutput
    case authenticationFailed
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .alreadyConnected:
            return "已经连接到服务器"
        case .notConnected:
            return "未连接到服务器"
        case .connectionFailed:
            return "连接失败"
        case .processCreationFailed:
            return "无法创建 SSH 进程"
        case .commandFailed(let message):
            return "命令执行失败: \(message)"
        case .invalidOutput:
            return "无效的输出格式"
        case .authenticationFailed:
            return "认证失败"
        case .timeout:
            return "认证超时"
        }
    }
}
