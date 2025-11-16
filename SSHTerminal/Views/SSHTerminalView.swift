import SwiftUI

struct SSHTerminalView: View {
    @StateObject private var viewModel = SSHTerminalViewModel()
    
    var body: some View {
        HStack(spacing: 0) {
            ConnectionListView(viewModel: viewModel)
                .frame(width: 300)
            
            Divider()
            
            TerminalView(viewModel: viewModel)
            
            Divider()
            
            FileBrowserView(viewModel: viewModel)
                .frame(width: 300)
        }
        .frame(minWidth: 1200, minHeight: 800)
    }
}
