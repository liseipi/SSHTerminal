import SwiftUI

struct FileItemRow: View {
    let item: FileItem
    let level: Int
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if item.type == .directory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 12)
                } else {
                    Spacer()
                        .frame(width: 12)
                }
                
                Image(systemName: item.type == .directory ? "folder.fill" : "doc.fill")
                    .foregroundColor(item.type == .directory ? .yellow : .gray)
                    .font(.caption)
                
                Text(item.name)
                    .font(.system(size: 12))
                
                Spacer()
                
                if let size = item.size {
                    Text(size)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, CGFloat(level * 16 + 12))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if item.type == .directory {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileItemRow(item: child, level: level + 1)
                }
            }
        }
    }
}
