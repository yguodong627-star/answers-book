import SwiftUI

struct NoteEditor: View {
    let entry: RecordSnapshot
    let session: DrawSession
    @State private var draft: String
    @State private var saveFailure: String?
    @Environment(\.dismiss) private var dismiss

    init(entry: RecordSnapshot, session: DrawSession) {
        self.entry = entry; self.session = session
        _draft = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(entry.zh).font(.custom("NotoSerifSC-Regular", size: 23))
                    Text(entry.en).font(.custom("Georgia", size: 16)).foregroundStyle(PaperTheme.muted)
                    Text("我的问题或备注（选填）").font(.headline).padding(.top, 12)
                    TextEditor(text: $draft)
                        .frame(minHeight: 230).padding(10)
                        .scrollContentBackground(.hidden)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        .autocorrectionDisabled()
                        .accessibilityLabel("我的问题或备注").accessibilityIdentifier("note-editor")
                    Button("清空内容") { draft = "" }
                        .disabled(draft.isEmpty).accessibilityIdentifier("note-clear")
                    if let saveFailure {
                        Text(saveFailure).foregroundStyle(.red).font(.footnote).accessibilityIdentifier("note-error")
                    }
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PaperTheme.paper).foregroundStyle(PaperTheme.ink)
            .navigationTitle("问题或备注").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("note-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if session.saveNote(id: entry.id, text: draft) { dismiss() }
                        else { saveFailure = session.failure }
                    }.accessibilityIdentifier("note-save")
                }
            }
        }.tint(PaperTheme.gold).preferredColorScheme(.light)
    }
}
