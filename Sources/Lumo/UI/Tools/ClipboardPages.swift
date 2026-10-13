import AppKit
import LumoCore
import SwiftUI

struct ClipboardPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: ClipboardStore
    @State private var query = ""

    var body: some View {
        let t = model.t
        let items = store.sortedEntries.filter { $0.matches(query) }
        TabScroll {
            LumoCard {
                SettingToggle(symbol: "doc.on.clipboard.fill", colors: FeatureID.clipboard.colors,
                              title: t("Запоминать скопированное", "Remember what you copy"),
                              subtitle: t("Только на этом Mac. Пароли из менеджеров не сохраняются.",
                                          "Stays on this Mac. Password-manager copies are skipped."),
                              isOn: $store.isEnabled)
                Divider().opacity(0.4)
                SettingToggle(symbol: "keyboard.fill", colors: [Palette.blue.color, Palette.indigo.color],
                              title: t("Окно по ⇧⌘V", "Panel on ⇧⌘V"),
                              subtitle: t("Поиск и вставка прямо в приложение", "Search and paste right into the app"),
                              isOn: $store.panelHotkey)
                Divider().opacity(0.4)
                SettingRow(symbol: "tray.full.fill", colors: [Palette.orange.color, Palette.yellow.color],
                           title: t("Хранить записей", "Keep entries")) {
                    Picker("", selection: $store.limit) {
                        ForEach([50, 100, 200, 500], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            .appear(order: 0).scrollFade()

            ClipboardExtrasCard(extras: model.clipExtras).appear(order: 0).scrollFade()

            if store.isEnabled && !model.input.accessibilityGranted && store.panelHotkey {
                PermissionCard(permission: .accessibility,
                               reason: t("Чтобы вставлять выбранное прямо в приложение (⌘V за вас).", "To paste the chosen item straight into your app."))
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                TextField(t("Поиск по истории", "Search history"), text: $query).textFieldStyle(.plain).font(.system(size: 12))
                if !store.entries.isEmpty {
                    Button(t("Очистить", "Clear")) { store.clearUnpinned() }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .appear(order: 1)

            if items.isEmpty {
                Text(store.isEnabled ? t("Скопируйте что-нибудь — оно появится здесь", "Copy something — it shows up here")
                                     : t("Включите историю выше", "Turn history on above"))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.top, 24)
            }
            ForEach(items) { entry in
                ClipRow(store: store, entry: entry)
                    .onTapGesture { store.copy(entry) }
                    .overlay(alignment: .trailing) {
                        HStack(spacing: 4) {
                            Button { store.togglePin(entry) } label: {
                                Image(systemName: entry.pinned ? "pin.slash.fill" : "pin")
                            }
                            Button { store.delete(entry) } label: { Image(systemName: "trash") }
                        }
                        .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary).padding(.trailing, 44)
                    }
                    .scrollFade()
            }
        }
    }
}

struct SnippetsPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SnippetStore
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        let t = model.t
        TabScroll {
            if store.isEnabled && !model.input.accessibilityGranted {
                PermissionCard(permission: .accessibility,
                               reason: t("Чтобы замечать сокращения, которые вы печатаете.", "To notice the shortcuts you type."))
            }
            LumoCard {
                SettingToggle(symbol: "text.badge.plus", colors: FeatureID.snippets.colors,
                              title: t("Разворачивать сниппеты", "Expand snippets"),
                              subtitle: t("Наберите сокращение в любом приложении", "Type a shortcut in any app"),
                              isOn: $store.isEnabled)
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("Новый сниппет", "New snippet")).appear(order: 1)
            LumoCard {
                TextField(t("Сокращение, например ;addr", "Shortcut, e.g. ;addr"), text: $trigger)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $expansion)
                    .font(.system(size: 12))
                    .frame(height: 64)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                HStack {
                    Text(t("Можно {date}, {time}, {clipboard}", "Supports {date}, {time}, {clipboard}"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Добавить", "Add")) {
                        store.add(trigger: trigger, expansion: expansion)
                        trigger = ""
                        expansion = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trigger.isEmpty || expansion.isEmpty)
                }
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Ваши сниппеты", "Your snippets"), trailing: "\(store.snippets.count)").appear(order: 3)
            ForEach(store.snippets) { snippet in
                HStack(alignment: .top, spacing: 10) {
                    Text(snippet.trigger)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient(colors: FeatureID.snippets.colors, startPoint: .leading, endPoint: .trailing)))
                        .foregroundStyle(.white)
                    Text(snippet.expansion).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button { store.delete(snippet) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                .modifier(ListRow())
                .scrollFade()
            }
        }
    }
}
