import SwiftUI
import AVFoundation

// MARK: - Slider + editable number

/// Slider with an editable number next to it: drag for coarse changes, type the
/// exact value (Enter or click away) when the slider will not land on it.
struct NumberSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    /// Display multiplier, e.g. 100 to show a 0...1 fraction as percent.
    let scale: Double
    let unit: String

    @State private var text = ""
    @FocusState private var focused: Bool

    init(title: String,
         value: Binding<Double>,
         range: ClosedRange<Double>,
         step: Double = 1,
         scale: Double = 1,
         unit: String = "") {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.scale = scale
        self.unit = unit
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Slider(value: $value, in: range, step: step)
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 54)
                    .focused($focused)
                    .onSubmit(commit)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: sync)
        .onChange(of: value) { _, _ in
            if !focused { sync() }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func sync() {
        text = format(value)
    }

    /// Parse what was typed, snap to the step, clamp to the range.
    private func commit() {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let typed = Double(cleaned) else {
            sync()
            return
        }
        let raw = typed / scale
        let snapped = (raw / step).rounded() * step
        value = min(max(snapped, range.lowerBound), range.upperBound)
        sync()
    }

    private func format(_ v: Double) -> String {
        let shown = v * scale
        if step * scale >= 1 {
            return String(Int(shown.rounded()))
        }
        return String(format: "%.1f", shown)
    }
}

// MARK: - Text appearance

struct TextSettingsPopover: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Picker("Шрифт", selection: $settings.fontName) {
                ForEach(SettingsStore.availableFonts, id: \.self) { name in
                    Text(name == "System" ? "Системный" : name).tag(name)
                }
            }
            Toggle("Жирный", isOn: $settings.isBold)

            NumberSliderRow(title: "Размер", value: $settings.fontSize, range: 16...72)
            NumberSliderRow(title: "Межстрочный", value: $settings.lineSpacing, range: 0...30)
            NumberSliderRow(title: "Отступы", value: $settings.horizontalMargin, range: 0...80)

            Picker("Выравнивание", selection: $settings.alignment) {
                Image(systemName: "text.alignleft").tag(0)
                Image(systemName: "text.aligncenter").tag(1)
                Image(systemName: "text.alignright").tag(2)
            }
            .pickerStyle(.segmented)

            ColorPicker("Цвет текста", selection: Binding(
                get: { Color(hex: settings.textColorHex) },
                set: { settings.textColorHex = $0.toHex() }
            ), supportsOpacity: false)

            ColorPicker("Цвет фона", selection: Binding(
                get: { Color(hex: settings.bgColorHex) },
                set: { settings.bgColorHex = $0.toHex() }
            ), supportsOpacity: false)

            NumberSliderRow(title: "Прозрачность фона", value: $settings.bgOpacity,
                            range: 0.1...1.0, step: 0.01, scale: 100, unit: "%")

            Toggle("Зеркальный текст (по горизонтали)", isOn: $settings.mirrorHorizontal)
            Toggle("Зеркальный текст (по вертикали)", isOn: $settings.mirrorVertical)
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 500)
    }
}

// MARK: - Prompter behavior

struct PrompterSettingsPopover: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            NumberSliderRow(title: "Скорость", value: $settings.speed, range: 1...100)
            LabeledContent("Обратный отсчёт") {
                HStack(spacing: 6) {
                    TextField("", value: Binding(
                        get: { settings.countdownSeconds },
                        set: { settings.countdownSeconds = min(max($0, 0), 10) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 54)
                    Stepper("", value: $settings.countdownSeconds, in: 0...10)
                        .labelsHidden()
                    Text("с")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Повтор по кругу (луп)", isOn: $settings.loopMode)
            Toggle("Показывать суфлёр при записи", isOn: $settings.showPanelOnRecord)

            Section("Окно суфлёра") {
                Toggle("Крепить под камерой (notch)", isOn: $settings.panelPinnedToNotch)
                NumberSliderRow(title: "Ширина", value: $settings.panelWidth, range: 300...1600)
                NumberSliderRow(title: "Высота", value: $settings.panelTextHeight, range: 80...800)
                NumberSliderRow(title: "Строка чтения", value: $settings.anchorFraction,
                                range: 0.05...0.6, step: 0.01, scale: 100, unit: "%")
                Text("Размер можно менять и мышью: потяните за левый, правый или нижний край окна суфлёра.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Прятать от записи экрана (Zoom/OBS)", isOn: $settings.hideFromScreenCapture)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 500)
        .onChange(of: settings.panelPinnedToNotch) { _, _ in app.reloadPanelIfVisible() }
        .onChange(of: settings.panelWidth) { _, _ in app.applyPanelGeometry() }
        .onChange(of: settings.panelTextHeight) { _, _ in app.applyPanelGeometry() }
        .onChange(of: settings.hideFromScreenCapture) { _, _ in app.reloadPanelIfVisible() }
    }
}

// MARK: - Camera

struct CameraSettingsPopover: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var capture: CaptureManager
    @EnvironmentObject var recordings: RecordingsStore

    @State private var diagnosticsCopied = false

    var body: some View {
        Form {
            Picker("Камера", selection: $settings.selectedCameraID) {
                Text("Авто (встроенная)").tag("")
                ForEach(capture.cameras, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID)
                }
            }
            Picker("Микрофон", selection: $settings.selectedMicID) {
                Text("Авто").tag("")
                ForEach(capture.microphones, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID)
                }
            }
            Toggle("Зеркальное превью", isOn: $settings.mirrorPreview)
            Toggle("Текст поверх превью", isOn: $settings.overlayTextOnPreview)

            Section("Состояние") {
                LabeledContent("Сигнал") {
                    Text(capture.isSessionRunning ? capture.activeFormatInfo : "камера выключена")
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                }
                if let err = capture.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button {
                    capture.copyDiagnosticsToClipboard()
                    diagnosticsCopied = true
                } label: {
                    Label(diagnosticsCopied ? "Диагностика скопирована — вставьте в сообщение" : "Скопировать диагностику",
                          systemImage: diagnosticsCopied ? "checkmark" : "doc.on.doc")
                }
            }

            Section("Записи") {
                Picker("Куда сохранять", selection: $settings.recordingsFolder) {
                    Text("Загрузки").tag("downloads")
                    Text("Документы").tag("documents")
                    Text("Фильмы").tag("movies")
                }
                Button {
                    recordings.openFolder()
                } label: {
                    Label("Открыть папку записей", systemImage: "folder")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 500)
        .onAppear { capture.refreshDevices() }
        .onChange(of: settings.selectedCameraID) { _, _ in capture.applyDeviceSelection() }
        .onChange(of: settings.selectedMicID) { _, _ in capture.applyDeviceSelection() }
        .onChange(of: settings.recordingsFolder) { _, _ in recordings.refresh() }
    }
}
