import SwiftUI

/// The scrolling text content shown inside the floating notch panel.
struct PrompterView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine: ScrollEngine
    let topInset: CGFloat
    let pinned: Bool

    /// Speed increment of the HUD +/- buttons (arrow keys use ±5).
    static let hudSpeedStep: Double = 1

    @State private var hovering = false
    @State private var speedText = ""
    @FocusState private var speedFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            PanelShape(pinned: pinned)
                .fill(Color(hex: settings.bgColorHex).opacity(settings.bgOpacity))

            VStack(spacing: 0) {
                // The menu-bar / notch strip: black zone that merges with the
                // notch. Record button lives here so the eyes never leave the camera.
                if topInset > 0 {
                    topStrip
                        .frame(height: topInset)
                }
                textArea
            }

            // In floating mode there is no strip — keep the record button
            // in the top-right corner instead.
            if topInset <= 0 {
                HStack {
                    if state.recordingState == .recording {
                        recordingBadge
                    }
                    Spacer()
                    recordButton
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

            if case .countingDown(let n) = state.recordingState {
                countdownOverlay(n)
            }

            // Keep the HUD while the speed number is being typed, even if
            // the mouse wandered off the panel.
            if hovering || speedFieldFocused {
                controlsHUD
            }
            if hovering {
                resizeGrips
            }
        }
        .clipShape(PanelShape(pinned: pinned))
        .onHover { hovering = $0 }
    }

    // MARK: - Top strip (menu bar zone)

    private var topStrip: some View {
        HStack {
            if state.recordingState == .recording {
                recordingBadge
            }
            Spacer()
            recordButton
        }
        .padding(.horizontal, 12)
    }

    private var recordingBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Text(timeString(state.recordingSeconds))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
        }
    }

    /// Start/stop recording without looking away from the camera.
    private var recordButton: some View {
        Button {
            state.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                switch state.recordingState {
                case .recording:
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                case .countingDown:
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 13, height: 13)
                case .idle:
                    Circle()
                        .fill(Color.red)
                        .frame(width: 13, height: 13)
                }
            }
            .contentShape(Circle().scale(1.6))
        }
        .buttonStyle(.plain)
        .help(state.recordingState == .idle ? "Начать запись" : "Остановить")
    }

    private func countdownOverlay(_ n: Int) -> some View {
        ZStack {
            Color.black.opacity(0.45)
            Text("\(n)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Text

    private var textArea: some View {
        GeometryReader { geo in
            let anchorY = geo.size.height * settings.anchorFraction
            ZStack(alignment: .topLeading) {
                Text(engine.text.isEmpty ? "Текст скрипта пуст.\nОткройте CamPrompt и напишите его." : engine.text)
                    .font(settings.font())
                    .foregroundColor(Color(hex: settings.textColorHex))
                    .lineSpacing(settings.lineSpacing)
                    .multilineTextAlignment(settings.textAlignment)
                    .frame(width: geo.size.width - CGFloat(settings.horizontalMargin) * 2,
                           alignment: settings.frameAlignment)
                    // Take the FULL laid-out height (otherwise Text truncates
                    // itself with "…" to the panel height and never scrolls on).
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(key: ContentHeightKey.self, value: textGeo.size.height)
                        }
                    )
                    .padding(.horizontal, CGFloat(settings.horizontalMargin))
                    .offset(y: anchorY - engine.offset)

                // Reading anchor line
                Rectangle()
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(height: 2)
                    .offset(y: anchorY - 4)
                    .padding(.horizontal, 6)
            }
            .scaleEffect(
                x: settings.mirrorHorizontal ? -1 : 1,
                y: settings.mirrorVertical ? -1 : 1
            )
            .onPreferenceChange(ContentHeightKey.self) { h in
                engine.contentHeight = h
                engine.viewportHeight = geo.size.height
            }
        }
        .clipped()
        .contentShape(Rectangle())
        // Tap on the text itself = play / pause.
        .onTapGesture { engine.togglePlay() }
    }

    // MARK: - HUD

    private var controlsHUD: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                hudButton(engine.isPlaying ? "pause.fill" : "play.fill") { engine.togglePlay() }
                hudButton("backward.end.fill") { engine.restart() }
                // Step 1: the HUD is for fine tuning (hitting exactly 20 or
                // 21). Coarse jumps are the arrow keys (±5) or typing the
                // number into the field between the buttons.
                hudButton("minus") { settings.speed = max(1, settings.speed - PrompterView.hudSpeedStep) }
                speedField
                hudButton("plus") { settings.speed = min(100, settings.speed + PrompterView.hudSpeedStep) }
                hudButton("xmark") { state.hidePanel() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            // Solid dark capsule: `.ultraThinMaterial` rendered white in the
            // light system appearance and hid the white icons.
            .background(Color.black.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .padding(.bottom, 10)
        }
        .transition(.opacity)
    }

    /// Speed as an editable number: click, type 1–100, Enter. Works because
    /// the panel can become key without activating the app (see
    /// ScrollForwardingPanel.canBecomeKey).
    private var speedField: some View {
        TextField("", text: $speedText)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .frame(width: 38, height: 20)
            .background(
                Color.white.opacity(speedFieldFocused ? 0.25 : 0.12),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .focused($speedFieldFocused)
            .onSubmit {
                commitSpeed()
                speedFieldFocused = false
            }
            .onAppear { speedText = "\(Int(settings.speed))" }
            .onChange(of: settings.speed) { _, v in
                if !speedFieldFocused { speedText = "\(Int(v))" }
            }
            .onChange(of: speedFieldFocused) { _, focused in
                if !focused { commitSpeed() }
            }
            .help("Скорость: нажмите на число и введите 1–100")
    }

    private func commitSpeed() {
        let cleaned = speedText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        if let v = Double(cleaned) {
            settings.speed = min(max(v.rounded(), 1), 100)
        }
        speedText = "\(Int(settings.speed))"
    }

    private func hudButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Resize grips

    /// Decorative only: the edge drag is intercepted by ScrollForwardingPanel.
    private var resizeGrips: some View {
        ZStack {
            HStack {
                grip(vertical: true)
                Spacer()
                grip(vertical: true)
            }
            .padding(.horizontal, 3)
            VStack {
                Spacer()
                grip(vertical: false)
            }
            .padding(.bottom, 3)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func grip(vertical: Bool) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.4))
            .frame(width: vertical ? 3 : 36, height: vertical ? 36 : 3)
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Rounded only at the bottom when pinned to the notch (the top edge
/// touches the physical screen edge), rounded everywhere when floating.
struct PanelShape: Shape {
    let pinned: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        if pinned {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                           control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                           control: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        } else {
            return Path(roundedRect: rect, cornerRadius: r)
        }
    }
}
