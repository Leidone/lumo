import AppKit
import SwiftUI

/// Auto-clear and plain-text paste, shown on the Clipboard page.
struct ClipboardExtrasCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var extras: ClipboardExtras

    var body: some View {
        let t = model.t
        LumoCard {
            SettingRow(symbol: "timer", colors: [Palette.red.color, Palette.orange.color],
                       title: t("Очищать буфер через", "Clear the clipboard after"),
                       subtitle: t("История Lumo при этом остаётся", "Lumo's history keeps its copy")) {
                Picker("", selection: $extras.clearAfterMinutes) {
                    Text(t("Никогда", "Never")).tag(0)
                    ForEach([1, 5, 15, 60], id: \.self) { Text(t("\($0) мин", "\($0) min")).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Divider().opacity(0.4)
            SettingToggle(symbol: "moon.zzz.fill", colors: [Palette.indigo.color, Palette.purple.color],
                          title: t("Очищать при сне", "Clear on sleep"), isOn: $extras.clearOnSleep)
            Divider().opacity(0.4)
            SettingToggle(symbol: "lock.fill", colors: [Palette.purple.color, Palette.pink.color],
                          title: t("Очищать при блокировке", "Clear on lock"), isOn: $extras.clearOnLock)
            Divider().opacity(0.4)
            SettingToggle(symbol: "textformat", colors: [Palette.green.color, Palette.mint.color],
                          title: t("Вставка без форматирования ", "Paste as plain text ") + (ShortcutStore.shared.binding(.pastePlain)?.display ?? ""),
                          subtitle: t("Исходное содержимое буфера возвращается обратно", "The original clipboard is put back afterwards"),
                          isOn: $extras.pastePlainEnabled)
        }
    }
}

struct ShelfPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var panel: ShelfPanelController

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingToggle(symbol: "hand.wave.fill", colors: FeatureID.shelf.colors,
                              title: t("Встряхнуть при перетаскивании", "Shake while dragging"),
                              subtitle: t("Тащите файл, текст или ссылку и покачайте курсором — полка появится рядом",
                                          "Drag a file, text or link and wiggle the pointer — the shelf appears right there"),
                              isOn: $panel.shakeToOpen)
                Divider().opacity(0.4)
                SettingToggle(symbol: "keyboard.fill", colors: [Palette.blue.color, Palette.indigo.color],
                              title: t("Открывать по ", "Open with ") + (ShortcutStore.shared.binding(.shelf)?.display ?? ""),
                              isOn: $panel.hotKeyEnabled)
                Button { panel.toggle() } label: {
                    Label(t("Показать полку", "Show the shelf"), systemImage: "tray.full.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("На полке", "On the shelf"), trailing: "\(shelf.items.count)").appear(order: 1)
            IslandFilesTab(shelf: shelf, t: t)
                .frame(height: 150)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.8)))
                .environment(\.colorScheme, .dark)
                .foregroundStyle(.white)
                .appear(order: 2)
            Text(t("Полка также живёт в Dynamic Island: перетащите файл на вырез.", "The shelf also lives in the Dynamic Island: drag a file onto the notch."))
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}

struct FileToolsPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var extras: ClipboardExtras
    @ObservedObject var installer: DMGInstaller

    var body: some View {
        let t = model.t
        TabScroll {
            SectionTitle(text: t("Ссылки без трекеров", "Links without trackers")).appear(order: 0)
            LumoCard {
                SettingToggle(symbol: "link.badge.plus", colors: FeatureID.fileTools.colors,
                              title: t("Чистить скопированные ссылки сами", "Clean copied links automatically"),
                              subtitle: extras.cleanedLinks > 0
                                  ? t("Очищено ссылок: \(extras.cleanedLinks)", "Links cleaned: \(extras.cleanedLinks)")
                                  : t("Убирает utm_, fbclid, gclid, si и другие метки слежки", "Removes utm_, fbclid, gclid, si and other tracking tags"),
                              isOn: $extras.autoCleanLinks)
                Button { extras.cleanClipboardLink() } label: {
                    Label(t("Очистить ссылку в буфере сейчас", "Clean the link on the clipboard now"), systemImage: "wand.and.rays")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .appear(order: 1).scrollFade()

            SectionTitle(text: "Finder").appear(order: 2)
            if extras.usesTap && !model.input.accessibilityGranted {
                PermissionCard(permission: .accessibility, reason: t("Чтобы перехватывать ⌘X, ⌘V и F2 в Finder.", "To catch ⌘X, ⌘V and F2 in Finder."))
            }
            LumoCard {
                SettingToggle(symbol: "scissors", colors: [Palette.orange.color, Palette.red.color],
                              title: t("⌘X и ⌘V перемещают файлы", "⌘X and ⌘V move files"), isOn: $extras.finderCutPaste)
                Divider().opacity(0.4)
                SettingToggle(symbol: "pencil.line", colors: [Palette.blue.color, Palette.cyan.color],
                              title: t("F2 — переименовать", "F2 renames"), isOn: $extras.finderRename)
                Divider().opacity(0.4)
                SettingToggle(symbol: "photo.badge.plus", colors: [Palette.green.color, Palette.mint.color],
                              title: t("⌘V вставляет картинку файлом PNG", "⌘V pastes an image as a PNG file"),
                              subtitle: t("В открытую папку Finder. macOS один раз спросит про управление Finder.",
                                          "Into the open Finder folder. macOS asks once to let Lumo control Finder."),
                              isOn: $extras.finderPasteImage)
            }
            .appear(order: 3).scrollFade()

            SectionTitle(text: t("Установка из DMG", "Install from DMG")).appear(order: 4)
            LumoCard {
                SettingToggle(symbol: "externaldrive.fill.badge.plus", colors: [Palette.purple.color, Palette.indigo.color],
                              title: t("Предлагать установку", "Offer to install"),
                              subtitle: t("Открыли образ с приложением — Lumo скопирует его в «Программы» и извлечёт диск",
                                          "Open a disk image with an app — Lumo copies it to Applications and ejects the disk"),
                              isOn: $installer.isEnabled)
                Divider().opacity(0.4)
                SettingToggle(symbol: "trash.fill", colors: [Palette.red.color, Palette.pink.color],
                              title: t("Потом удалить .dmg из «Загрузок»", "Then move the .dmg from Downloads to Trash"),
                              isOn: $installer.trashImage)
            }
            .appear(order: 5).scrollFade()
        }
    }
}
