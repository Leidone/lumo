import AppKit
import UniformTypeIdentifiers

/// "Share an expiring link": uploads one file to litterbox.catbox.moe (no account, deleted after 24 hours)
/// only when the user presses the button, after a one-time confirmation. The link lands on the clipboard.
@MainActor
enum LinkUploader {
    private static let endpoint = URL(string: "https://litterbox.catbox.moe/resources/internals/api.php")!
    private static let consentKey = "upload.consented"
    private static let maxBytes = 1_000_000_000

    static func share(_ file: URL, t: Localizer) async {
        guard confirm(t) else { return }
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size < maxBytes else {
            Toast.show("exclamationmark.triangle.fill", t("Файл слишком большой для ссылки (до 1 ГБ)", "Too large for a link (1 GB max)"), tint: Palette.orange.color)
            return
        }
        Toast.show("icloud.and.arrow.up.fill", t("Загружаю…", "Uploading…"), subtitle: file.lastPathComponent)
        guard let link = await upload(file) else {
            Toast.show("xmark.octagon.fill", t("Не получилось загрузить", "Upload failed"), tint: Palette.red.color)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        Toast.show("link", t("Ссылка скопирована · живёт 24 часа", "Link copied · lives 24 hours"), subtitle: link.absoluteString, tint: Palette.green.color)
    }

    /// Asks once; the answer is remembered.
    private static func confirm(_ t: Localizer) -> Bool {
        if UserDefaults.standard.bool(forKey: consentKey) { return true }
        let alert = NSAlert()
        alert.messageText = t("Поделиться временной ссылкой?", "Share a temporary link?")
        alert.informativeText = t("Файл будет загружен на litterbox.catbox.moe — внешний бесплатный сервис — и удалится через 24 часа. Любой, у кого есть ссылка, сможет его открыть.",
                                  "The file is uploaded to litterbox.catbox.moe — an external free service — and deleted after 24 hours. Anyone with the link can open it.")
        alert.addButton(withTitle: t("Загрузить", "Upload"))
        alert.addButton(withTitle: t("Отмена", "Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: consentKey)
        return true
    }

    private static func upload(_ file: URL) async -> URL? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let boundary = "lumo-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("reqtype", "fileupload")
        field("time", "24h")
        let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let name = file.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"fileToUpload\"; filename=\"\(name)\"\r\nContent-Type: \(type)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        guard let (response, status) = try? await URLSession.shared.upload(for: request, from: body),
              (status as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        let text = String(decoding: response, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }
}
