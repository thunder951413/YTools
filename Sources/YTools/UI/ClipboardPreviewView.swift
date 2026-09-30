import SwiftUI

struct ClipboardPreviewView: View {
    @ObservedObject var preview: ClipboardPreviewController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("内容预览").font(.headline)
                Spacer()
                Button { preview.hide() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("关闭剪贴板预览")
            }
            Divider()
            if let item = preview.item {
                if preview.isLoading {
                    ProgressView("正在读取加密原件…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = preview.error {
                    Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let image = preview.image {
                    Image(decorative: image.image, scale: 1).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("图片原件预览，\(image.width) × \(image.height)")
                    Text("原件 \(image.width) × \(image.height)").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.vertical) {
                        Text(item.payload.joined(separator: item.kind == .files ? "\n\n" : "\n"))
                            .font(.system(size: 13)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .accessibilityLabel(item.kind == .files ? "完整文件路径" : "剪贴板全文")
                }
                Text(item.sourceApplication ?? "未知来源").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("选择一条记录查看内容").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}
