import SwiftUI

// Send links to a space (idea 255; #595, #721): links to chosen sites open
// in their space, with its sign-ins, as Arc's Air Traffic Control does.
// After @AdityaAmitK's #596 and #722, made smaller.
//
// Off unless turned on in Settings › Spaces & Pins, and only with spaces on.
// A rule is a site, its subdomains with it, an optional path, and a space.
// The most specific site wins, then its longest matching path. It sends:
//
// - a link from another app (Search as the Mac's browser);
// - a link a page opens in a new tab — a target="_blank" click, ⌘-click,
//   the middle button, Open Link in New Tab — from a page in another space.
//
// The tab opens in that space, and the window that has it, or this one
// switched to it, comes to it. A link followed in its own tab, an address
// typed, a private tab's links, a window the page sizes ("Sign in with…",
// which needs its opener) and anything that isn't http or https stay where
// they are. So does a link whose rule names a space that has gone: the rule
// is passed over, and the link opens as it always did.

struct SpaceRoute: Equatable, Identifiable {
    /// A host, lowercased, without www.: "notion.so".
    var site: String
    /// An optional, case-sensitive path prefix, ending on a path boundary.
    /// Nil keeps the original rule for the whole site and its subdomains.
    var path: String?
    var space: UUID
    var id: String { site + (path ?? "") }

    /// As it is kept in the settings: a plain dictionary, readable with
    /// `defaults read`.
    var plist: [String: String] {
        var values = ["site": site, "space": space.uuidString]
        if let path { values["path"] = path }
        return values
    }

    init(site: String, space: UUID, path: String? = nil) {
        self.site = site
        self.space = space
        self.path = path
    }

    init?(plist: Any) {
        guard let entry = plist as? [String: String],
              let site = entry["site"].flatMap(SpaceRoutes.site), let space = entry["space"].flatMap(UUID.init)
        else { return nil }
        if let path = entry["path"] {
            guard path.hasPrefix("/"), !path.contains("?"), !path.contains("#"),
                  let url = URL(string: "https://route.invalid" + path) else { return nil }
            self.init(site: site, space: space, path: SpaceRoutes.path(of: url))
        } else {
            self.init(site: site, space: space)
        }
    }
}

enum SpaceRoutes {
    static let key = "spaces.links"
    static let rulesKey = "spaces.links.rules"
    private static let escapes = try! NSRegularExpression(pattern: "%[0-9a-fA-F]{2}")

    /// A site or a URL entered in Settings. Unlike site(_:), keep its path;
    /// query strings and fragments never decide which space gets a link.
    static func route(_ typed: String, to space: UUID) -> SpaceRoute? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("*.") { text.removeFirst(2) }
        if !text.contains("://") {
            // Tab menus hand us an already-normalized IPv6 host without
            // brackets; add them back before treating it as a URL.
            if !text.contains("/"), !text.hasPrefix("["), text.filter({ $0 == ":" }).count > 1 {
                text = "[" + text + "]"
            }
            text = "https://" + text
        }
        guard let url = URL(string: text), let site = site(of: url),
              url.user == nil, url.password == nil else { return nil }
        return SpaceRoute(site: site, space: space, path: path(of: url))
    }

    static func path(of url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var path = components.percentEncodedPath
        // Escape spelling is insensitive to hex case, while path text is
        // not. Keep encoded slashes encoded so they cannot invent segments.
        let original = path as NSString
        for match in escapes.matches(in: path, range: NSRange(location: 0, length: original.length)) {
            let escape = original.substring(with: match.range)
            path = path.replacingOccurrences(of: escape, with: escape.uppercased())
        }
        // Web addresses treat escaped dots as dot segments too. Resolve
        // them before choosing a space, without decoding an escaped slash
        // or a dot that is part of an ordinary filename.
        path = path.split(separator: "/", omittingEmptySubsequences: false).map { segment in
            let dots = segment.replacingOccurrences(of: "%2E", with: ".")
            return dots == "." || dots == ".." ? dots : String(segment)
        }.joined(separator: "/")
        components.percentEncodedPath = path
        if let resolved = components.url?.standardized,
           let normalized = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
            path = normalized.percentEncodedPath
        }
        while path.hasSuffix("/") { path.removeLast() }
        return path.isEmpty ? nil : path
    }

    // MARK: - sites

    /// What was typed, as the site a rule keeps: "https://www.Notion.so/x",
    /// "notion.so" and "*.notion.so" are all "notion.so". Nil for anything
    /// that isn't a host.
    static func site(_ typed: String) -> String? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("*.") { text.removeFirst(2) }
        guard !text.isEmpty else { return nil }
        if !text.contains("://"), !text.contains("/"), !text.hasPrefix("["), text.filter({ $0 == ":" }).count > 1 {
            text = "[" + text + "]"
        }
        if !text.contains("://") { text = "https://" + text }
        // URL.host uses the same ASCII spelling as site(of:), including
        // international domain names restored from an older settings file.
        guard let host = URL(string: text)?.host else { return nil }
        return clean(host)
    }

    /// The site of a web address; nil for anything but http and https.
    static func site(of url: URL) -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host else { return nil }
        return clean(host.lowercased())
    }

    private static func clean(_ host: String) -> String? {
        var host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www."), host.dropFirst(4).contains(".") { host.removeFirst(4) }
        guard !host.isEmpty, host.count <= 253,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == ":" })
        else { return nil }
        // An IPv6 address as it is; a name has no empty label, and one with
        // no dot is only ever localhost.
        if host.contains(":") { return host }
        guard host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
              host.contains(".") || host == "localhost"
        else { return nil }
        return host
    }

    // MARK: - matching

    /// The rule for an address: the one whose site is its host or a domain
    /// of it, the longest such site when more than one is.
    static func match(_ url: URL, in routes: [SpaceRoute]) -> SpaceRoute? {
        guard let host = site(of: url) else { return nil }
        let path = path(of: url) ?? ""
        return routes
            .filter { host == $0.site || (!host.contains(":") && host.hasSuffix("." + $0.site)) }
            .filter { route in
                guard let prefix = route.path else { return true }
                return path == prefix || path.hasPrefix(prefix + "/")
            }
            .max {
                if $0.site.count != $1.site.count { return $0.site.count < $1.site.count }
                return ($0.path?.count ?? 0) < ($1.path?.count ?? 0)
            }
    }

    enum TabMenuAction: Equatable {
        case remove(SpaceRoute, destination: String?)
        case set(site: String, space: Space)

        var title: String {
            switch self {
            case let .remove(route, destination):
                // A broader rule may still apply after this one is removed.
                // Name the rule, rather than promise that routing will stop.
                return "Remove Rule: \(route.id)" + (destination.map { " → \($0)" } ?? " (space removed)")
            case let .set(site, space):
                return "Always Open \(site) in \(space.name)"
            }
        }

        @MainActor func run() {
            switch self {
            case let .remove(route, _): SpaceRoutes.remove(route.id)
            case let .set(site, space): SpaceRoutes.set(site, to: space.id)
            }
        }
    }

    /// The tab can be in a different space from the rule's destination.
    /// Offer the rule that actually matches, including a parent domain or
    /// path, and keep whole-site creation for a page with no matching rule.
    static func tabMenuAction(for url: URL, routes: [SpaceRoute], current: Space,
                              spaces: [UUID: Space]) -> TabMenuAction? {
        guard let site = site(of: url) else { return nil }
        if let route = match(url, in: routes) {
            return .remove(route, destination: spaces[route.space]?.name)
        }
        return .set(site: site, space: current)
    }

    /// The space a rule sends an address to: only while the setting and
    /// spaces are both on, and only a space that is still there.
    static func space(for url: URL, routes: [SpaceRoute], on: Bool, spaces: [UUID: Space]) -> Space? {
        guard on, let route = match(url, in: routes) else { return nil }
        return spaces[route.space]
    }

    @MainActor static func space(for url: URL) -> Space? {
        let prefs = Shared.prefs
        return space(for: url, routes: prefs.spaceRoutes, on: prefs.usesSpaces && prefs.sendsLinksToSpaces,
                     spaces: Spaces.known)
    }

    /// One site/path to one space, leaving other paths of that site intact.
    @MainActor static func set(_ site: String, to space: UUID) {
        guard let route = route(site, to: space) else { return }
        var routes = Shared.prefs.spaceRoutes
        if let at = routes.firstIndex(where: { $0.id == route.id }) {
            routes[at] = route
        } else {
            routes.append(route)
        }
        Shared.prefs.spaceRoutes = routes
    }

    @MainActor static func remove(_ id: String) {
        Shared.prefs.spaceRoutes.removeAll { $0.id == id }
    }

    // MARK: - windows

    /// The window that is to show `space`: one on screen already in it, the
    /// one in front first; otherwise `source`, or a window of the space's
    /// profile, switched to it. Nil if it couldn't be.
    @MainActor static func window(for space: Space, from source: Browser) -> Browser? {
        let windows = ([Browsers.front].compactMap { $0 } + Browsers.all.reversed()).filter { $0.isOpen && !$0.isPopup }
        if let shown = windows.first(where: { $0.spaceID == space.id }) { return shown }
        let window = space.profileID == source.profileID ? source : Browsers.open(profile: space.profileID)
        guard window.prefs.usesSpaces else { return nil }
        window.switchSpace(to: space.id)
        // With profiles in one window, the switch can bring that profile's
        // window into this one's place (see OneWindow.swift).
        return ([window] + Browsers.all.reversed()).first { $0.isOpen && !$0.isPopup && $0.spaceID == space.id }
    }

    /// The spaces a rule can name, with the profile's name before each once
    /// there is more than one profile.
    @MainActor static var choices: [(id: UUID, name: String)] {
        let profiles = Profiles.shared
        return Spaces.read().map { space in
            (space.id, profiles.several ? "\(profiles.profile(space.profileID).name) › \(space.name)" : space.name)
        }
    }
}

extension Browser {
    /// For a link from another app: the window a rule sends it to, already
    /// in its space. Nil to open it as always.
    func routed(_ url: URL) -> Browser? {
        guard !isPopup, let space = SpaceRoutes.space(for: url), space.id != spaceID else { return nil }
        return SpaceRoutes.window(for: space, from: self)
    }

    /// A link a page opens in a new tab, opened in front in the space a rule
    /// sends it to. False when no rule sends it out of the page's space.
    func sendToSpace(_ url: URL, from source: Tab?) -> Bool {
        guard !isPopup, let source, !source.shy, let space = SpaceRoutes.space(for: url) else { return false }
        let here = parked.first { $0.value.tabs.contains { $0 === source } }?.key ?? spaceID
        guard space.id != here, let target = SpaceRoutes.window(for: space, from: self) else { return false }
        target.open(url, foreground: true)
        if target !== self { Browsers.show(target) }
        return true
    }
}

/// Settings › Spaces & Pins, under Send links to a space: each site and its
/// space, and a line to add one.
struct SpaceRouteList: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var profiles = Profiles.shared
    @State private var typed = ""
    @State private var chosen: UUID?

    var body: some View {
        let choices = SpaceRoutes.choices
        let canAdd = SpaceRoutes.route(typed, to: chosen ?? choices.first?.id ?? Space.firstID) != nil
        ForEach(prefs.spaceRoutes) { route in
            Rule()
            Line(route.id, choices.first { $0.id == route.space }.map { "Opens in \($0.name)" }
                 ?? "Its space is gone, so links open as usual") {
                Pill("Remove") { SpaceRoutes.remove(route.id) }
            }
        }
        Rule()
        HStack(spacing: 10) {
            TextField("notion.so or notion.so/work", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onSubmit(add)
            Picker("Space", selection: Binding(get: { chosen ?? choices.first?.id }, set: { chosen = $0 })) {
                ForEach(choices, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Pill("Add", action: add)
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func add() {
        guard let space = chosen ?? SpaceRoutes.choices.first?.id,
              SpaceRoutes.route(typed, to: space) != nil else { return }
        SpaceRoutes.set(typed, to: space)
        typed = ""
    }
}
