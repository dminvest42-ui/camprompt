import SwiftUI
import AVFoundation

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

            LabeledContent("Размер: \(Int(settings.fontSize))") {
                Slider(value: $settings.fontSize, in: 16...72)
            }
            LabeledContent("Межстрочный: \(Int(settings.lineSpacing))") {
                Slider(value: $settings.lineSpacing, in: 0...30)
            }
            LabeledContent("Отступы: \(Int(settings.horizontalMargin))") {
                Slider(value: $settings.horizontalMargin, in: 0...80)
            }

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

            LabeledContent("Прозрачность фона") {
                Slider(value: $settings.bgOpacity, in: 0.1...1.0)
            }

            Toggle("Зеркальный текст (по горизонтали)", isOn: $settings.mirrorHorizontal)
            Toggle("Зеркальный текст (по вертикали)", isOn: $settings.mirrorVertical)
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 470)
    }
}

// MARK: - Prompter behavior

struct PrompterSettingsPopover: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            LabeledContent("Скорость: \(Int(settings.speed))") {
                Slider(value: $settings.speed, in: 1...100)
            }
            Stepper("Обратный отсчёт: \(settings.countdownSeconds) c",
                    value: $settings.countdownSeconds, in: 0...10)
            Toggle("Повтор по кругу (луп)", isOn: $settings.loopMode)
            Toggle("Показывать суфлёр при записи", isOn: $settings.showPanelOnRecord)

            Section("Окно суфлёра") {
                Toggle("Крепить под камерой (notch)", isOn: $settings.panelPinnedToNotch)
                LabeledContent("Ширина: \(Int(settings.panelWidth))") {
                    Slider(value: $settings.panelWidth, in: 300...1200)
                }
                LabeledContent("Высота: \(Int(settings.panelTextHeight))") {
                    Slider(value: $settings.panelTextHeight, in: 80...500)
                }
                LabeledContent("Строка чтения") {
                    Slider(value: $settings.anchorFraction, in: 0.05...0.6)
                }
                Toggle("Прятать от записи экрана (Zoom/OBS)", isOn: $settings.hideFromScreenCapture)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 430)
        .onChange(of: settings.panelPinnedToNotch) { _, _ in app.reloadPanelIfVisible() }
        .onChange(of: settings.panelWidth) { _, _ in app.reloadPanelIfVisible() }
        .onChange(of: settings.panelTextHeight) { _, _ in app.reloadPanelIfVisible() }
        .onChange(of: settings.hideFromScreenCapture) { _, _ in app.reloadPanelIfVisible() }
    }
}

// MARK: - Camera

struct CameraSettingsPopover: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var capture: CaptureManager
    @EnvironmentObject var recordings: RecordingsStore

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

            Section {
                Button {
                    recordings.openFolder()
                } label: {
                    Label("Папка записей (~/Movies/Teleprompter)", systemImage: "folder")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 300)
        .onAppear { capture.refreshDevices() }
        .onChange(of: settings.selectedCameraID) { _, _ in capture.applyDeviceSelection() }
        .onChange(of: settings.selectedMicID) { _, _ in capture.applyDeviceSelection() }
    }
}
