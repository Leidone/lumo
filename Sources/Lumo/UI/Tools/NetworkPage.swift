import AppKit
import LumoCore
import SwiftUI

/// Live traffic, totals since Lumo started, the local address and Apple's speed test.
struct NetworkPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var speedTest: SpeedTester

    var body: some View {
        let t = model.t
        let network = model.snapshot.network
        TabScroll {
            LumoCard(padding: 16) {
                HStack(spacing: 10) {
                    rate("arrow.down.circle.fill", t("Загрузка", "Download"), Format.rate(network.downRate), [Palette.cyan.color, Palette.blue.color])
                    rate("arrow.up.circle.fill", t("Отдача", "Upload"), Format.rate(network.upRate), [Palette.purple.color, Palette.pink.color])
                }
                Divider().opacity(0.4)
                row(t("За сессию: получено", "This session: received"), Format.bytes(network.sessionDown))
                row(t("За сессию: отправлено", "This session: sent"), Format.bytes(network.sessionUp))
                if let ip = network.localIP {
                    HStack {
                        Text(t("Локальный IP", "Local IP")).font(.system(size: 12))
                        Spacer()
                        Text(ip).font(.system(size: 12, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ip, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("Тест скорости", "Speed test")).appear(order: 1)
            LumoCard {
                switch speedTest.state {
                case .idle:
                    Text(t("Встроенный в macOS тест Apple. Займёт около 20 секунд и потратит немного трафика.",
                           "Apple's test built into macOS. Takes about 20 seconds and uses some data."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                case .running:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(t("Измеряю…", "Measuring…")).font(.system(size: 12))
                    }
                case .done(let result):
                    HStack(spacing: 10) {
                        rate("arrow.down", t("Загрузка", "Download"), String(format: "%.0f Mbit/s", result.downloadMbps), [Palette.cyan.color, Palette.blue.color])
                        rate("arrow.up", t("Отдача", "Upload"), String(format: "%.0f Mbit/s", result.uploadMbps), [Palette.purple.color, Palette.pink.color])
                    }
                    if let latency = result.latencyMilliseconds {
                        row(t("Задержка", "Latency"), String(format: "%.0f ms", latency))
                    }
                    if let rpm = result.responsiveness {
                        row(t("Отзывчивость под нагрузкой", "Responsiveness under load"), "\(Int(rpm)) RPM")
                    }
                case .failed:
                    Text(t("Не получилось — проверьте подключение к интернету.", "That didn't work — check your internet connection."))
                        .font(.system(size: 11.5)).foregroundStyle(Palette.orange.color)
                }
                Button { speedTest.run() } label: {
                    Label(speedTest.state == .running ? t("Остановить", "Stop") : t("Проверить скорость", "Run speed test"),
                          systemImage: speedTest.state == .running ? "stop.fill" : "speedometer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .appear(order: 2).scrollFade()
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: speedTest.state)
        }
    }

    private func rate(_ symbol: String, _ title: String, _ value: String, _ colors: [Color]) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, colors: colors, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}
