import SwiftUI

struct AccountMenu: View {
    let instanceName: String
    let syncModel: SyncStatusModel?
    let signOut: () -> Void

    var body: some View {
        Menu {
            Text(instanceName)
            if let syncModel {
                SyncStatusMenuItem(model: syncModel)
                Divider()
            }
            Button("Sign out", role: .destructive, action: signOut)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.crop.circle")
                if let syncModel {
                    Circle()
                        .fill(SyncStatusPresentation(syncModel.status).color)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.background, lineWidth: 1.5))
                }
            }
            .accessibilityLabel("Account")
            .accessibilityValue(
                syncModel.map { SyncStatusPresentation($0.status).title } ?? ""
            )
        }
    }
}

private struct SyncStatusMenuItem: View {
    @Bindable var model: SyncStatusModel

    var body: some View {
        let presentation = SyncStatusPresentation(model.status)
        if presentation.canRetry {
            Button {
                Task { await model.retry() }
            } label: {
                Label(
                    model.isRetrying ? "Reconnecting…" : presentation.title,
                    systemImage: presentation.systemImage
                )
            }
            .disabled(model.isRetrying)
            .accessibilityIdentifier("retry-sync")
        } else {
            Label(presentation.title, systemImage: presentation.systemImage)
                .accessibilityIdentifier("sync-status")
        }
    }
}

private struct SyncStatusPresentation {
    let title: String
    let systemImage: String
    let color: Color
    let canRetry: Bool

    init(_ status: VegaSyncStatus) {
        if let rejection = status.rejection {
            title = "Couldn’t sync \(rejection.table) change"
            systemImage = "exclamationmark.triangle.fill"
            color = .red
            canRetry = false
        } else if status.errorMessage != nil {
            title = "Sync interrupted — retry"
            systemImage = "arrow.clockwise.circle.fill"
            color = .orange
            canRetry = true
        } else if status.uploading || status.downloading || status.connecting {
            title =
                status.pendingUploads == 1
                ? "Syncing 1 change…" : "Syncing \(status.pendingUploads) changes…"
            systemImage = "arrow.triangle.2.circlepath.circle.fill"
            color = .blue
            canRetry = false
        } else if !status.connected {
            title =
                status.pendingUploads == 1
                ? "Offline — 1 change waiting"
                : "Offline — \(status.pendingUploads) changes waiting"
            systemImage = "icloud.slash.fill"
            color = .orange
            canRetry = true
        } else if status.pendingUploads > 0 {
            title =
                status.pendingUploads == 1
                ? "1 change waiting to sync"
                : "\(status.pendingUploads) changes waiting to sync"
            systemImage = "clock.arrow.circlepath"
            color = .orange
            canRetry = true
        } else {
            title = "Synced"
            systemImage = "checkmark.icloud.fill"
            color = .green
            canRetry = false
        }
    }
}
