import SwiftUI

struct ConnectionListView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("SSH 连接", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.showAddForm.toggle() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if viewModel.showAddForm {
                AddConnectionForm(viewModel: viewModel)
                Divider()
            }
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.connections) { connection in
                        ConnectionRow(
                            connection: connection,
                            isActive: viewModel.activeConnection?.id == connection.id,
                            onConnect: { viewModel.connect(to: connection) },
                            onDelete: { viewModel.deleteConnection(connection) }
                        )
                        Divider()
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}
