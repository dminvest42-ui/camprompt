import SwiftUI
import AVFoundation

struct MainWindowView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var scripts: ScriptStore
    @EnvironmentObject var capture: CaptureManager
    @EnvironmentObject var engine: ScrollEngine
    @EnvironmentObject var recordings: RecordingsStore

    @State private var showTextSettings = false
    @State private var showPrompterSettings = false
    @State private var showCameraSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
        }
        .toolbar { toolbarContent }
        .onAppear {
            capture.refreshDevices()
            capture.startCamera()
        }
        .onChange(of: scripts.selectedID) { _, _ in
            engine.text = scripts.selectedScript?.text ?? ""
            engine.restart()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $scripts.selectedID) {
            Section("Скрипты") {
                ForEach(scripts.scripts) { script in
                    Label(script.title.isEmpty ? "Без названия" : script.title,
                          systemImage: "doc.text")
                        .tag(script.id)
                        .contextMenu {
                            Button("Удалить", role: .destructive) { scripts.delete(script) }
                        }
                }
            }
            Section("Записи") {
                if recordings.items.isEmpty {
                    Text("Пока нет записей")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(recordings.items.prefix(10)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                            Text(String(format: "%.1f МБ", item.sizeMB))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .contextMenu {
                            Button("Открыть") { recordings.open(item) }
                            Button("Показать в Finder") { recordings.revealInFinder(item) }
                        }
                        .onTapGesture(count: 2) { recordings.open(item) }
                    }
                    Button {
                        recordings.openFolder()
                    } label: {
                        Label("Открыть папку записей", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    scripts.addScript()
                } label: {
                    Label("Новый скрипт", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Detail

    private var detail: some View {
        HStack(spacing: 0) {
            editorPane
                .frame(minWidth: 340)
            Divider()
            cameraPane
                .frame(minWidth: 400)
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            if let script = scripts.selectedScript {
                TextField("Название скрипта", text: Binding(
                    get: { script.title },
                    set: { scripts.update(id: script.id, title: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)

                TextEditor(text: Binding(
                    get: { scripts.selectedScript?.text ?? "" },
                    set: { scripts.update(id: script.id, text: $0) }
                ))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                ContentUnavailableView("Нет скрипта",
                                       systemImage: "doc.text",
                                       description: Text("Создайте новый скрипт кнопкой «+» слева."))
            }
        }
    }

    private var cameraPane: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)

                if capture.isSessionRunning {
                    CameraPreviewView(session: capture.session, mirrored: settings.mirrorPreview)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        if let err = capture.lastError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        Button("Включить камеру") { capture.startCamera() }
                    }
                }

                if settings.overlayTextOnPreview, capture.isSessionRunning {
                    previewTextOverlay
                }

                if case .countingDown(let n) = app.recordingState {
                    Color.black.opacity(0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("\(n)")
                        .font(.system(size: 110, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }

                if app.recordingState == .recording {
                    VStack {
                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(Color.red).frame(width: 9, height: 9)
                                Text(String(format: "%02d:%02d", app.recordingSeconds / 60, app.recordingSeconds % 60))
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.85), in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .padding([.horizontal, .top], 16)

            recordControls
                .padding(.bottom, 14)
        }
    }

    private var previewTextOverlay: some View {
        GeometryReader { geo in
            let anchorY = geo.size.height * settings.anchorFraction
            Text(engine.text)
                .font(settings.font())
                .foregroundColor(Color(hex: settings.textColorHex).opacity(0.9))
                .lineSpacing(settings.lineSpacing)
                .multilineTextAlignment(settings.textAlignment)
                .frame(width: geo.size.width * 0.86, alignment: settings.frameAlignment)
                .offset(y: anchorY - engine.offset)
                .frame(maxWidth: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    private var recordControls: some View {
        HStack(spacing: 18) {
            Button {
                capture.isSessionRunning ? capture.stopCamera() : capture.startCamera()
            } label: {
                Image(systemName: capture.isSessionRunning ? "video.fill" : "video.slash.fill")
                    .font(.system(size: 16))
            }
            .help(capture.isSessionRunning ? "Выключить камеру" : "Включить камеру")

            Spacer()

            Button {
                app.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.25), lineWidth: 3)
                        .frame(width: 54, height: 54)
                    if app.recordingState == .recording {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.red)
                            .frame(width: 24, height: 24)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 42, height: 42)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!capture.isSessionRunning && app.recordingState == .idle)
            .help(app.recordingState == .recording ? "Остановить запись" : "Начать запись")

            Spacer()

            Button {
                app.togglePanel()
            } label: {
                Image(systemName: app.panelVisible ? "rectangle.topthird.inset.filled" : "rectangle.topthird.inset")
                    .font(.system(size: 16))
            }
            .help(app.panelVisible ? "Скрыть суфлёр" : "Показать суфлёр под камерой")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showTextSettings.toggle()
            } label: {
                Label("Текст", systemImage: "textformat")
            }
            .popover(isPresented: $showTextSettings) {
                TextSettingsPopover()
                    .environmentObject(settings)
            }

            Button {
                showPrompterSettings.toggle()
            } label: {
                Label("Суфлёр", systemImage: "slider.horizontal.3")
            }
            .popover(isPresented: $showPrompterSettings) {
                PrompterSettingsPopover()
                    .environmentObject(settings)
                    .environmentObject(app)
            }

            Button {
                showCameraSettings.toggle()
            } label: {
                Label("Камера", systemImage: "web.camera")
            }
            .popover(isPresented: $showCameraSettings) {
                CameraSettingsPopover()
                    .environmentObject(settings)
                    .environmentObject(capture)
                    .environmentObject(recordings)
            }
        }
    }
}
