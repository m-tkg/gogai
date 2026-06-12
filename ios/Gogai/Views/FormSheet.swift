import SwiftUI

/// 追加・編集フォーム共通のシェル。
/// NavigationStack + Form + エラー表示 + キャンセル/確定ツールバーと、
/// 「送信中フラグ・エラー保持・成功時 dismiss」の定型処理を提供する。
struct FormSheet<Content: View>: View {
    let title: String
    let confirmLabel: String
    var confirmDisabled: Bool = false
    let onSubmit: () async throws -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                content()

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) {
                        Task { await submit() }
                    }
                    .disabled(confirmDisabled || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await onSubmit()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// グループ選択の共通セクション（フィード追加・編集で使用）
struct GroupPickerSection: View {
    @EnvironmentObject private var groupStore: GroupStore
    @Binding var selectedGroupId: Int?

    var body: some View {
        Section("グループ（任意）") {
            Picker("グループ", selection: $selectedGroupId) {
                Text("なし").tag(Optional<Int>.none)
                ForEach(groupStore.groups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
        }
    }
}
