import SwiftUI

struct ConnectionRow: View {
    let connection: SSHConnection
    let isActive: Bool
    let onConnect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.name)
                    .font(.system(size: 14, weight: .medium))
                
                Text("\(connection.username)@\(connection.host):\(connection.port)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: connection.authType == .password ? "lock.fill" : "key.fill")
                        .font(.system(size: 10))
                    Text(connection.authType.rawValue)
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onConnect)
    }
}
