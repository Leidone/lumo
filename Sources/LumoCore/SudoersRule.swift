import Foundation

/// A sudoers rule that lets the current user run exactly Lumo's three maintenance
/// commands as root without a password — and nothing else.
public enum SudoersRule {
    public static let filePath = "/etc/sudoers.d/lumo"

    /// Exact command lines (sudo matches arguments literally).
    public static let commands: [[String]] = [
        ["/usr/sbin/purge"],
        ["/usr/bin/dscacheutil", "-flushcache"],
        ["/usr/bin/killall", "-HUP", "mDNSResponder"],
    ]

    /// Removing the file restores the password prompt.
    public static let removeScript = "/bin/rm -f \(filePath)"

    /// Short macOS user names only: anything else could inject into sudoers or the shell.
    public static func isValidUserName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z_][A-Za-z0-9_.-]{0,31}$", options: .regularExpression) != nil
    }

    public static func line(for user: String) -> String? {
        guard isValidUserName(user) else { return nil }
        let list = commands.map { $0.joined(separator: " ") }.joined(separator: ", ")
        return "\(user) ALL=(root) NOPASSWD: \(list)"
    }

    /// Root shell script: writes the rule inside the root-owned directory (no user-writable
    /// temp file to swap), validates it with visudo, then activates it with an atomic rename.
    /// sudo ignores file names containing a dot, so the staging file is never live.
    public static func installScript(for user: String) -> String? {
        guard let line = line(for: user) else { return nil }
        let staging = filePath + ".tmp"
        return "umask 0337; /bin/echo '\(line)' > \(staging)"
            + " && /usr/sbin/chown root:wheel \(staging)"
            + " && /usr/sbin/visudo -cf \(staging) >/dev/null"
            + " && /bin/mv -f \(staging) \(filePath)"
            + " || { /bin/rm -f \(staging); exit 1; }"
    }
}
