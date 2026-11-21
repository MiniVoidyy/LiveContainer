// LCAppListView.swift

import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct LCAppListView: View, LCAppModelDelegate {
    @StateObject var model = LCAppListModel()
    @Environment(\.scenePhase) var scenePhase
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingRenameSheet = false
    @State private var appToRename: LCAppModel?
    @State private var showingShareSheet = false
    @State private var appToShare: LCAppModel?
    @State private var showingMoveSheet = false
    @State private var appToMove: LCAppModel?
    @State private var showingDeleteConfirmation = false
    @State private var appToDelete: LCAppModel?
    @State private var showingContainerPicker = false
    @State private var appForContainerChange: LCAppModel?
    @State private var searchText = ""
    @State private var selectedApps: Set<UUID> = []
    @State private var showingMultiActionSheet = false
    @State private var multiActionType: MultiActionType?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if model.apps.isEmpty {
                    EmptyStateView()
                } else {
                    appList
                }
            }
            .navigationTitle("Apps")
            .searchable(text: $searchText, prompt: "Search apps")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showingContainerPicker = true }) {
                            Image(systemName: "folder")
                        }
                        Button(action: { showingMultiActionSheet = true }) {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingContainerPicker) {
                ContainerPickerView()
            }
            .confirmationDialog("Multi Action", isPresented: $showingMultiActionSheet, titleVisibility: .visible) {
                Button("Run Selected") { multiActionType = .run }
                Button("Hide Selected") { multiActionType = .hide }
                Button("Lock Selected") { multiActionType = .lock }
                Button("Unlock Selected") { multiActionType = .unlock }
                Button("Share Selected") { multiActionType = .share }
                Button("Delete Selected", role: .destructive) { multiActionType = .delete }
                Button("Cancel", role: .cancel) { selectedApps.removeAll() }
            } message: {
                Text("\(selectedApps.count) apps selected")
            }
            .alert(alertMessage, isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { await model.refreshApps() }
                }
            }
            .task {
                await model.refreshApps()
            }
        }
    }

    private var appList: some View {
        List {
            Section(header: Text("Installed Apps")) {
                ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                    AppRowView(app: app, index: index)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                appToDelete = app
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            Button { toggleFavorite(app) } label: {
                                Image(systemName: app.isFavorite ? "star.fill" : "star")
                            } .tint(.yellow)
                            Button { appToShare = app; showingShareSheet = true } label: {
                                Image(systemName: "square.and.arrow.up")
                            } .tint(.blue)
                        }
                        .sheet(item: $appToShare) { app in
                            ActivityViewController(activityItems: [app.appInfo.bundlePath ?? ""])
                        }
                        .confirmationDialog("Delete App", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                if let app = appToDelete {
                                    Task { await deleteApp(app) }
                                }
                            }
                        } message: {
                            Text("Are you sure you want to delete \(appToDelete?.displayName ?? "app")?")
                        }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func toggleFavorite(_ app: LCAppModel) {
        app.toggleFavorite()
    }

    private func deleteApp(_ app: LCAppModel) async {
        do {
            try await model.deleteApp(app)
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            let app = model.apps[index]
            Task { await deleteApp(app) }
        }
    }
}

struct AppRowView: View, LCAppModelDelegate {
    @ObservedObject var app: LCAppModel
    @State private var showingSettings = false
    @State private var showingLaunchOptions = false
    @State private var isRunning = false
    @State private var showingJITAlert = false
    @State private var jitAlertMessage = ""
    var index: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray6))
                    .frame(width: 70, height: 70)
                if let icon = app.appInfo.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 28))
                        .foregroundColor(.gray)
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(app.appInfo.bundleIdentifier() ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if app.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 10, weight: .bold))
                    }
                    if app.launchCount > 0 {
                        Image(systemName: "play.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                        Text("\(app.launchCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                    }
                    Spacer()
                    if app.isLocked {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 10, weight: .bold))
                    }
                    if app.isHidden {
                        Image(systemName: "eye.slash")
                            .foregroundColor(.gray)
                            .font(.system(size: 10, weight: .bold))
                    }
                    if app.uiIsJITNeeded {
                        Image(systemName: "bolt.circle")
                            .foregroundColor(.purple)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
            }
            Spacer()
            Button(action: {
                Task {
                    do {
                        try await app.runApp()
                    } catch {
                        jitAlertMessage = error.localizedDescription
                        showingJITAlert = true
                    }
                }
            }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .disabled(app.isAppRunning)
            .opacity(app.isAppRunning ? 0.5 : 1.0)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { showingSettings = true }
        .sheet(isPresented: $showingSettings) {
            LCAppSettingsView(app: app)
        }
        .alert(jitAlertMessage, isPresented: $showingJITAlert) {
            Button("OK", role: .cancel) { }
        }
    }
}

enum MultiActionType {
    case run, hide, lock, unlock, share, delete
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "app.dashed")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No apps installed")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Install guest apps to get started")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

class LCAppListModel: ObservableObject {
    @Published var apps: [LCAppModel] = []
    @Published var isRefreshing = false
    func refreshApps() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let appInfos = LCAppInfo.allApps()
        var newApps: [LCAppModel] = []
        for appInfo in appInfos {
            let app = LCAppModel(appInfo: appInfo)
            newApps.append(app)
        }
        await MainActor.run {
            self.apps = newApps.sorted { $0.displayName < $1.displayName }
        }
    }
    func deleteApp(_ app: LCAppModel) async throws {
        // Delete app logic
    }
}

// MARK: - LCAppModelDelegate
extension LCAppListView: LCAppModelDelegate {
    func closeNavigationView() { }
    func changeAppVisibility(app: LCAppModel) { }
    func jitLaunch(appName: String, classicMode: UInt) async { }
    func jitLaunch(withScript script: String, appName: String, classicMode: UInt) async { }
    func jitLaunch(withPID pid: Int, withScript script: String?, appName: String) async { }
    func showRunWhenMultitaskAlert() async -> Bool? { return true }
}