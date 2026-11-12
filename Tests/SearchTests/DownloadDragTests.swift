import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Search

final class DownloadDragTests: XCTestCase {
    private func withFile(_ body: (URL, Keep) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("download-drag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("report with spaces.txt")
        try Data("report".utf8).write(to: file)
        let keep = Keep(name: file.lastPathComponent, from: "test.invalid", path: file.path, date: Date())
        try body(file, keep)
    }

    func testCompletedFileExportsAFileURL() throws {
        try withFile { file, keep in
            XCTAssertEqual(keep.dragURL, file)
            let provider = try XCTUnwrap(keep.dragProvider())
            XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
            let loaded = expectation(description: "file URL")
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                XCTAssertNil(error)
                let received: URL?
                if let url = item as? URL { received = url }
                else if let data = item as? Data { received = URL(dataRepresentation: data, relativeTo: nil) }
                else if let text = item as? String { received = URL(string: text) }
                else { received = nil }
                XCTAssertEqual(received, file)
                loaded.fulfill()
            }
            wait(for: [loaded], timeout: 3)
        }
    }

    func testFileRemovedAfterTheRowDrewCannotBeDragged() throws {
        try withFile { file, keep in
            XCTAssertNotNil(keep.dragURL)
            try FileManager.default.removeItem(at: file)
            XCTAssertNil(keep.dragURL)
            XCTAssertNil(keep.dragProvider())
        }
    }

    func testDirectoryIsNotOfferedAsADownloadedFile() throws {
        try withFile { file, keep in
            var directory = keep
            directory.path = file.deletingLastPathComponent().path
            XCTAssertNil(directory.dragURL)
            XCTAssertNil(directory.dragProvider())
        }
    }
}
