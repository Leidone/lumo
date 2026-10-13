import AppKit
import LumoCore
import SwiftUI

struct ScreenshotPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var tools: CaptureTools

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let t = model.t
        TabScroll {
            if !model.input.screenRecordingGranted {
                PermissionCard(permission: .screenRecording,
                               reason: t("macOS разрешает делать снимки экрана только с этим доступом.", "macOS only allows screen captures with this access."))
            }
            LazyVGrid(columns: columns, spacing: 10) {
                actionTile("rectangle.dashed", t("Область", "Area"), "⌃⇧1", FeatureID.screenshot.colors) { run { tools.screenshot(.area) } }
                actionTile("macwindow", t("Окно", "Window"), "⌃⇧2", [Palette.blue.color, Palette.indigo.color]) { run { tools.screenshot(.window) } }
                actionTile("text.viewfinder", t("Текст с экрана", "Copy text"), "⌃⇧3", [Palette.green.color, Palette.mint.color]) {
                    run { tools.recognizeText() }
                }
                actionTile("eyedropper.halffull", t("Пипетка", "Color picker"), "⌃⇧4", [Palette.orange.color, Palette.pink.color]) {
                    run { tools.pickColor() }
                }
                actionTile("arrow.up.and.down.text.horizontal", t("С прокруткой", "Scrolling"), "", [Palette.cyan.color, Palette.blue.color]) {
                    run { tools.scrollingScreenshot() }
                }
                actionTile("display", t("Весь экран", "Whole screen"), "", [Palette.indigo.color, Palette.purple.color]) {
                    run { tools.screenshot(.screen) }
                }
                actionTile("web.camera.fill", t("Камера-зеркало", "Camera mirror"), "", [Palette.blue.color, Palette.purple.color]) {
                    model.cameraMirror.toggle()
                }
                actionTile("photo.on.rectangle.angled", t("Медиа-инструменты", "Media tools"), "", [Palette.pink.color, Palette.orange.color]) {
                    MediaToolsWindow.open(t: t)
                }
            }
            .appear(order: 0)

            LumoCard {
                SettingToggle(symbol: "scope", colors: [Palette.cyan.color, Palette.blue.color],
                              title: t("Селектор Lumo", "Lumo selector"),
                              subtitle: t("Режимы в одной панели, лупа с пикселями, прокрутка. Выключите — будет системный.",
                                          "All modes in one bar, a pixel loupe, scrolling. Off — the macOS one."),
                              isOn: $tools.useSelector)
                Divider().opacity(0.4)
                SettingToggle(symbol: "command", colors: [Palette.purple.color, Palette.indigo.color],
                              title: t("Горячие клавиши ⌃⇧1…5", "⌃⇧1…5 shortcuts"),
                              subtitle: t("Снимки, текст, пипетка и запись — из любого приложения", "Captures, text, picker and recording from any app"),
                              isOn: $tools.hotkeysEnabled)
                Divider().opacity(0.4)
                SettingRow(symbol: "paintpalette.fill", colors: [Palette.pink.color, Palette.orange.color],
                           title: t("Формат цвета", "Color format")) {
                    Picker("", selection: $tools.colorFormat) {
                        ForEach(CaptureTools.ColorFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            .appear(order: 1).scrollFade()

            if !tools.colors.isEmpty {
                SectionTitle(text: t("Недавние цвета", "Recent colors"), trailing: nil).appear(order: 2)
                LumoCard {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(tools.colors, id: \.hex) { color in
                            Button { tools.copy(color) } label: {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                                    .frame(height: 34)
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.2)))
                            }
                            .buttonStyle(PressScaleStyle())
                            .help("\(color.hex) · \(color.rgb)")
                        }
                    }
                    Button(t("Очистить", "Clear")) { tools.clearColors() }.buttonStyle(.borderless).font(.system(size: 11))
                }
                .appear(order: 3).scrollFade()
            }
        }
    }

    /// Closes the popover first so it never ends up in the capture.
    private func run(_ action: @escaping () -> Void) {
        NSApp.keyWindow?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action)
    }

    private func actionTile(_ symbol: String, _ title: String, _ shortcut: String, _ colors: [Color],
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                IconBadge(symbol: symbol, colors: colors, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(shortcut).font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct RecorderPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var recorder: ScreenRecorder

    var body: some View {
        let t = model.t
        TabScroll {
            if !model.input.screenRecordingGranted {
                PermissionCard(permission: .screenRecording, reason: t("Без него macOS не даст записать экран.", "macOS won't record the screen without it."))
            }
            LumoCard(padding: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: FeatureID.recorder.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)
                            .shadow(color: Palette.red.color.opacity(0.45), radius: 10)
                        Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                            .symbolEffect(.pulse, isActive: recorder.isRecording)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let started = recorder.startedAt {
                            Text(started, style: .timer).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        } else {
                            Text(t("Готов к записи", "Ready to record")).font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        Text(t("Экран под курсором · ⌃⇧5", "Screen under the pointer · ⌃⇧5")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                PrimaryButton(title: recorder.isRecording ? t("Остановить", "Stop") : t("Начать запись", "Start recording")) {
                    if recorder.isRecording {
                        recorder.toggle()
                    } else {
                        NSApp.keyWindow?.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { recorder.toggle() }
                    }
                }
                if let error = recorder.lastError {
                    Text(error).font(.system(size: 10.5)).foregroundStyle(Palette.orange.color)
                }
            }
            .appear(order: 0).scrollFade()

            LumoCard {
                SettingToggle(symbol: "speaker.wave.2.fill", colors: [Palette.blue.color, Palette.cyan.color],
                              title: t("Звук системы", "System audio"), subtitle: t("Отдельная дорожка", "Separate track"),
                              isOn: $recorder.systemAudio)
                Divider().opacity(0.4)
                SettingToggle(symbol: "mic.fill", colors: [Palette.orange.color, Palette.pink.color],
                              title: t("Микрофон", "Microphone"),
                              subtitle: recorder.supportsMicrophone ? t("Отдельная дорожка", "Separate track") : t("Нужна macOS 15", "Needs macOS 15"),
                              isOn: $recorder.microphone)
                    .disabled(!recorder.supportsMicrophone)
                Divider().opacity(0.4)
                SettingToggle(symbol: "cursorarrow", colors: [Palette.purple.color, Palette.indigo.color],
                              title: t("Показывать курсор", "Show the pointer"), isOn: $recorder.showCursor)
            }
            .disabled(recorder.isRecording)
            .appear(order: 1).scrollFade()

            if !recorder.recordings.isEmpty {
                SectionTitle(text: t("Записи", "Recordings"), trailing: "\(recorder.recordings.count)").appear(order: 2)
                ForEach(recorder.recordings.prefix(12), id: \.self) { url in
                    HStack(spacing: 10) {
                        IconBadge(symbol: url.pathExtension == "gif" ? "photo.stack.fill" : "film.fill",
                                  colors: url.pathExtension == "gif" ? [Palette.green.color, Palette.mint.color] : FeatureID.recorder.colors, size: 26)
                        Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 11.5)).lineLimit(1)
                        Spacer()
                        if url.pathExtension == "mp4" {
                            Button(t("Редактировать", "Edit")) { RecordingEditor.open(url, recorder: recorder, t: t) }
                                .controlSize(.small).buttonStyle(.bordered)
                            if recorder.exportingGIF == url {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("GIF") { recorder.exportGIF(url) }.controlSize(.small).buttonStyle(.bordered)
                            }
                        }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }
                            .buttonStyle(.borderless)
                    }
                    .modifier(ListRow())
                    .scrollFade()
                }
            }
        }
        .onAppear { recorder.reloadRecordings() }
    }
}
