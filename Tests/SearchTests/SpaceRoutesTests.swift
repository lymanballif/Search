import XCTest
@testable import Search

/// Send links to a space (SpaceRoutes.swift): what a rule's site is, which
/// rule an address meets, and that nothing is sent while it is off, with
/// spaces off, or to a space that has gone.
@MainActor
final class SpaceRoutesTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "space-routes-\(getpid())", 1)
        super.setUp()
    }

    private let work = Space(id: UUID(), name: "Work", colour: 0)
    private let home = Space(id: UUID(), name: "Home", colour: 0)
    private var spaces: [UUID: Space] { [work.id: work, home.id: home] }

    private func url(_ text: String) -> URL { URL(string: text)! }

    func testSitesAsTyped() {
        XCTAssertEqual(SpaceRoutes.site("notion.so"), "notion.so")
        XCTAssertEqual(SpaceRoutes.site("  https://www.Notion.so/page?x=1 "), "notion.so")
        XCTAssertEqual(SpaceRoutes.site("*.notion.so"), "notion.so")
        XCTAssertEqual(SpaceRoutes.site("Docs.Google.com."), "docs.google.com")
        XCTAssertEqual(SpaceRoutes.site("localhost:3000"), "localhost")
        XCTAssertEqual(SpaceRoutes.site("127.0.0.1"), "127.0.0.1")
        XCTAssertEqual(SpaceRoutes.site("www.com"), "www.com", "www. is only dropped before a domain")
        for nothing in ["", "   ", "notion", "a..b", "not a site", "https://"] {
            XCTAssertNil(SpaceRoutes.site(nothing), nothing)
        }
    }

    func testSiteOfAnAddressIsWebOnly() {
        XCTAssertEqual(SpaceRoutes.site(of: url("https://www.figma.com/file/1")), "figma.com")
        XCTAssertNil(SpaceRoutes.site(of: url("mailto:me@figma.com")))
        XCTAssertNil(SpaceRoutes.site(of: url("file:///tmp/a.html")))
        XCTAssertNil(SpaceRoutes.site(of: url("search://settings")))
    }

    func testSubdomainsMatchAndTheMostSpecificWins() {
        let routes = [SpaceRoute(site: "google.com", space: home.id), SpaceRoute(site: "docs.google.com", space: work.id)]
        XCTAssertEqual(SpaceRoutes.match(url("https://google.com/"), in: routes)?.space, home.id)
        XCTAssertEqual(SpaceRoutes.match(url("https://mail.google.com/x"), in: routes)?.space, home.id)
        XCTAssertEqual(SpaceRoutes.match(url("https://docs.google.com/d/1"), in: routes)?.space, work.id)
        XCTAssertEqual(SpaceRoutes.match(url("http://a.docs.google.com:8080/"), in: routes)?.space, work.id)
        XCTAssertEqual(SpaceRoutes.match(url("https://www.google.com/"), in: routes)?.space, home.id)
        XCTAssertNil(SpaceRoutes.match(url("https://notgoogle.com/"), in: routes), "a suffix is not a subdomain")
        XCTAssertNil(SpaceRoutes.match(url("https://google.com.evil.example/"), in: routes))
        XCTAssertNil(SpaceRoutes.match(url("ftp://google.com/"), in: routes))
    }

    func testLocalHostsMatchExactly() {
        let routes = [SpaceRoute(site: "localhost", space: work.id), SpaceRoute(site: "127.0.0.1", space: home.id)]
        XCTAssertEqual(SpaceRoutes.match(url("http://localhost:5173/"), in: routes)?.space, work.id)
        XCTAssertEqual(SpaceRoutes.match(url("http://127.0.0.1:8000/"), in: routes)?.space, home.id)
        XCTAssertNil(SpaceRoutes.match(url("http://[::1]:8000/"), in: routes))
    }

    func testOffSpacesOffAndGoneSpacesSendNothing() {
        let routes = [SpaceRoute(site: "figma.com", space: work.id), SpaceRoute(site: "gone.example", space: UUID())]
        let link = url("https://www.figma.com/file/1")
        XCTAssertEqual(SpaceRoutes.space(for: link, routes: routes, on: true, spaces: spaces), work)
        XCTAssertNil(SpaceRoutes.space(for: link, routes: routes, on: false, spaces: spaces))
        XCTAssertNil(SpaceRoutes.space(for: url("https://gone.example/"), routes: routes, on: true, spaces: spaces),
                     "a rule whose space has gone is passed over")
        XCTAssertNil(SpaceRoutes.space(for: url("https://other.example/"), routes: routes, on: true, spaces: spaces))
    }

    func testKeptAsPlainSettings() {
        let route = SpaceRoute(site: "figma.com", space: work.id)
        XCTAssertEqual(SpaceRoute(plist: route.plist), route)
        XCTAssertNil(SpaceRoute(plist: ["site": "figma.com"]))
        XCTAssertNil(SpaceRoute(plist: ["site": "not a site", "space": work.id.uuidString]))
        XCTAssertNil(SpaceRoute(plist: "figma.com"))
    }

    func testPathInputKeepsCaseAndDropsQueryAndFragment() throws {
        let route = try XCTUnwrap(SpaceRoutes.route(" https://www.Notion.so/Team/Project/?view=board#top ", to: work.id))
        XCTAssertEqual(route.site, "notion.so")
        XCTAssertEqual(route.path, "/Team/Project")
        XCTAssertEqual(route.id, "notion.so/Team/Project")
        XCTAssertEqual(SpaceRoutes.route("notion.so/", to: work.id)?.path, nil)
        XCTAssertEqual(SpaceRoutes.route("notion.so/a/../work", to: work.id)?.path, "/work")
        XCTAssertEqual(SpaceRoutes.route("::1", to: work.id)?.site, "::1")
        XCTAssertNil(SpaceRoutes.route("file:///tmp/work", to: work.id))
        XCTAssertNil(SpaceRoutes.route("https://user:password@notion.so/work", to: work.id))
    }

    func testPathRulesMatchWholeSegmentsAndMostSpecificPrefix() throws {
        let whole = SpaceRoute(site: "example.com", space: home.id)
        let workRoute = try XCTUnwrap(SpaceRoutes.route("example.com/Work", to: work.id))
        let nested = try XCTUnwrap(SpaceRoutes.route("example.com/Work/project", to: home.id))
        let routes = [nested, whole, workRoute]
        for address in ["https://example.com/Work", "https://example.com/Work/", "https://sub.example.com/Work/doc?q=1#section"] {
            XCTAssertEqual(SpaceRoutes.match(url(address), in: routes), workRoute, address)
        }
        for address in ["https://example.com/Workbook", "https://example.com/work", "https://example.com/other"] {
            XCTAssertEqual(SpaceRoutes.match(url(address), in: routes), whole, address)
        }
        XCTAssertEqual(SpaceRoutes.match(url("https://example.com/Work/project/doc"), in: routes), nested)
        let subdomain = SpaceRoute(site: "sub.example.com", space: home.id)
        XCTAssertEqual(SpaceRoutes.match(url("https://sub.example.com/Work/doc"), in: routes + [subdomain]), subdomain)
    }

    func testEscapedSlashDoesNotBecomeAPathBoundary() throws {
        let route = try XCTUnwrap(SpaceRoutes.route("example.com/team%2fwork", to: work.id))
        XCTAssertEqual(SpaceRoutes.match(url("https://example.com/team%2Fwork/doc"), in: [route]), route)
        XCTAssertNil(SpaceRoutes.match(url("https://example.com/team/work/doc"), in: [route]))
        let team = try XCTUnwrap(SpaceRoutes.route("example.com/team", to: home.id))
        XCTAssertNil(SpaceRoutes.match(url("https://example.com/team%2Fwork/doc"), in: [team]))
    }

    func testEscapedDotSegmentsMatchTheResolvedPage() throws {
        let workRoute = try XCTUnwrap(SpaceRoutes.route("example.com/work", to: work.id))
        let homeRoute = try XCTUnwrap(SpaceRoutes.route("example.com/home", to: home.id))
        for dots in ["%2e%2e", ".%2E", "%2e."] {
            XCTAssertEqual(SpaceRoutes.match(url("https://example.com/work/\(dots)/home"), in: [workRoute, homeRoute]), homeRoute)
        }
        XCTAssertEqual(SpaceRoutes.route("example.com/work/%2e/child", to: work.id)?.path, "/work/child")
        XCTAssertEqual(SpaceRoutes.route("example.com/work/file%2Etxt", to: work.id)?.path, "/work/file%2Etxt")
    }

    func testInternationalDomainsKeepMatchingAfterPersistence() throws {
        let route = try XCTUnwrap(SpaceRoutes.route("bücher.de/work", to: work.id))
        XCTAssertEqual(route.site, "xn--bcher-kva.de")
        let restored = try XCTUnwrap(SpaceRoute(plist: route.plist))
        XCTAssertEqual(restored, route)
        XCTAssertEqual(SpaceRoutes.match(url("https://bücher.de/work/page"), in: [restored]), restored)
        let legacy = try XCTUnwrap(SpaceRoute(plist: ["site": "bücher.de", "space": work.id.uuidString]))
        XCTAssertEqual(legacy.site, route.site)
        XCTAssertEqual(SpaceRoutes.match(url("https://xn--bcher-kva.de/other"), in: [legacy]), legacy)
    }

    func testPathRulesPersistBesideWholeSiteRules() throws {
        let whole = SpaceRoute(site: "example.com", space: home.id)
        let path = try XCTUnwrap(SpaceRoutes.route("example.com/work/", to: work.id))
        XCTAssertNil(whole.plist["path"], "old whole-site dictionaries stay unchanged")
        XCTAssertEqual(SpaceRoute(plist: path.plist), path)
        let local = try XCTUnwrap(SpaceRoutes.route("http://[::1]:8000/work", to: work.id))
        XCTAssertEqual(SpaceRoute(plist: local.plist), local)
        XCTAssertNotEqual(whole.id, path.id)
        XCTAssertNil(SpaceRoute(plist: ["site": "example.com", "path": "work", "space": work.id.uuidString]))

        let previous = Shared.prefs.spaceRoutes
        defer { Shared.prefs.spaceRoutes = previous }
        Shared.prefs.spaceRoutes = [whole]
        SpaceRoutes.set("example.com/work/", to: work.id)
        XCTAssertEqual(Shared.prefs.spaceRoutes, [whole, path])
        SpaceRoutes.set("example.com/work", to: home.id)
        XCTAssertEqual(Shared.prefs.spaceRoutes.count, 2)
        SpaceRoutes.remove("example.com")
        XCTAssertEqual(Shared.prefs.spaceRoutes.map(\.id), [path.id])
    }

    func testOffByDefaultFindableAndKeptBetweenRuns() {
        let keys = [SpaceRoutes.key, SpaceRoutes.rulesKey]
        let saved = keys.map { ($0, Store.settings.object(forKey: $0)) }
        defer { for (key, value) in saved { Store.settings.set(value, forKey: key) } }
        keys.forEach(Store.settings.removeObject(forKey:))
        let prefs = Preferences()
        XCTAssertFalse(prefs.sendsLinksToSpaces)
        XCTAssertTrue(prefs.spaceRoutes.isEmpty)
        prefs.spaceRoutes = [SpaceRoute(site: "figma.com", space: work.id)]
        XCTAssertEqual(Preferences().spaceRoutes, prefs.spaceRoutes)
        for words in ["send links", "air traffic control", "open in space", "routing"] {
            XCTAssertTrue(SettingsIndex.find(words).contains { $0.id == "spaces.links" }, words)
        }
        XCTAssertEqual(SettingsIndex.item("spaces.links")?.page, .spaces)
        XCTAssertEqual(SettingsIndex.item("spaces.links")?.parent, "spaces")
    }

    func testTabMenuRemovesTheMatchingPathRuleFromAnotherSpace() throws {
        let whole = SpaceRoute(site: "example.com", space: home.id)
        let path = SpaceRoute(site: "example.com", space: work.id, path: "/Work")
        let sibling = SpaceRoute(site: "example.com", space: work.id, path: "/Personal")
        let previous = Shared.prefs.spaceRoutes
        defer { Shared.prefs.spaceRoutes = previous }
        Shared.prefs.spaceRoutes = [whole, path, sibling]

        let action = try XCTUnwrap(SpaceRoutes.tabMenuAction(for: url("https://example.com/Work/doc"),
            routes: Shared.prefs.spaceRoutes, current: home, spaces: spaces))
        XCTAssertEqual(action, .remove(path, destination: "Work"))
        XCTAssertEqual(action.title, "Remove Rule: example.com/Work → Work")
        action.run()
        XCTAssertEqual(Shared.prefs.spaceRoutes, [whole, sibling], "Only the displayed rule is removed")
        XCTAssertEqual(SpaceRoutes.match(url("https://example.com/Work/doc"), in: Shared.prefs.spaceRoutes), whole)
    }

    func testTabMenuNamesTheEffectiveParentOrMoreSpecificHostRule() throws {
        let parent = SpaceRoute(site: "example.com", space: work.id, path: "/Work")
        let specific = SpaceRoute(site: "docs.example.com", space: home.id)
        let address = url("https://docs.example.com/Work/doc?view=1#section")
        XCTAssertEqual(SpaceRoutes.tabMenuAction(for: address, routes: [parent], current: home, spaces: spaces),
                       .remove(parent, destination: "Work"))
        let action = try XCTUnwrap(SpaceRoutes.tabMenuAction(for: address, routes: [parent, specific],
                                                            current: work, spaces: spaces))
        XCTAssertEqual(action, .remove(specific, destination: "Home"))
        XCTAssertEqual(action.title, "Remove Rule: docs.example.com → Home")
    }

    func testTabMenuCanRemoveARuleWhoseDestinationWasDeleted() throws {
        let gone = SpaceRoute(site: "example.com", space: UUID(), path: "/Work")
        let action = try XCTUnwrap(SpaceRoutes.tabMenuAction(for: url("https://example.com/Work"),
                                                            routes: [gone], current: home, spaces: spaces))
        XCTAssertEqual(action, .remove(gone, destination: nil))
        XCTAssertEqual(action.title, "Remove Rule: example.com/Work (space removed)")
    }

    func testTabMenuStillCreatesAWholeSiteRuleForAnUnmatchedPage() throws {
        let path = SpaceRoute(site: "example.com", space: work.id, path: "/Work")
        let previous = Shared.prefs.spaceRoutes
        defer { Shared.prefs.spaceRoutes = previous }
        Shared.prefs.spaceRoutes = [path]

        let action = try XCTUnwrap(SpaceRoutes.tabMenuAction(for: url("https://example.com/Workbook"),
            routes: Shared.prefs.spaceRoutes, current: home, spaces: spaces))
        XCTAssertEqual(action, .set(site: "example.com", space: home))
        XCTAssertEqual(action.title, "Always Open example.com in Home")
        action.run()
        XCTAssertEqual(Shared.prefs.spaceRoutes, [path, SpaceRoute(site: "example.com", space: home.id)])
        XCTAssertNil(SpaceRoutes.tabMenuAction(for: url("file:///tmp/page.html"), routes: [],
                                               current: home, spaces: spaces))
    }
}
