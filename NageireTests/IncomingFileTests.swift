import Foundation
import Testing
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
@testable import Nageire

struct IncomingFileTests {
    @Test func anItemOfTextIsTextAndAnyOtherDataIsAFile() {
        #expect(IncomingFile.isFile([.pdf]))
        #expect(IncomingFile.isFile([.png]))
        #expect(!IncomingFile.isFile([.utf8PlainText]))
        #expect(!IncomingFile.isFile([.utf8PlainText, .png]))
        #expect(!IncomingFile.isFile([]))
    }

    @Test func aFileAtAURLIsKnownByItsNameAndSizeBeforeItIsRead() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "IncomingFileTests-\(UUID().uuidString).pdf")
        try Data("%PDF-1.7".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try IncomingFile(url: url)

        #expect(file.name == url.lastPathComponent)
        #expect(file.size == 8)
        #expect(try file.read() == Data("%PDF-1.7".utf8))
    }

    #if os(macOS)
    @Test @MainActor func aPasteboardWithFilesGivesTheFilesOneWithTextGivesNoneAndAnImageAloneGivesAnImageWithoutAName() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("IncomingFileTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appending(path: "IncomingFileTests-\(UUID().uuidString).pdf")
        try Data("%PDF".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        pasteboard.clearContents()
        // The Finder puts the file's name as text beside the file.
        pasteboard.writeObjects([url as NSURL, url.lastPathComponent as NSString])
        #expect(IncomingFile.files(on: pasteboard).map(\.name) == [url.lastPathComponent])

        pasteboard.clearContents()
        pasteboard.setString("text", forType: .string)
        #expect(IncomingFile.files(on: pasteboard).isEmpty)

        pasteboard.clearContents()
        pasteboard.setData(pngData(width: 2, height: 2), forType: .png)
        let image = try #require(IncomingFile.files(on: pasteboard).first)
        #expect(image.name == nil)
    }
    #endif
}
