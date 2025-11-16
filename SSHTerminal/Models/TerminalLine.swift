import SwiftUI

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let type: LineType
    
    enum LineType {
        case system, command, output, error, prompt
        
        var color: Color {
            switch self {
            case .system: return .green
            case .command: return .white
            case .output: return .gray
            case .error: return .red
            case .prompt: return .blue
            }
        }
    }
}
