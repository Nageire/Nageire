import Foundation
import Testing
@testable import Nageire

struct AttachmentTests {
    @Test func aPlainNameIsKeptAndADecomposedOneIsPrecomposed() {
        #expect(Attachment.fileName(for: "IMG_0421.jpeg", avoiding: []) == "IMG_0421.jpeg")
        #expect(Attachment.fileName(for: "写真.jpg".decomposedStringWithCanonicalMapping, avoiding: []) == "写真.jpg")
    }

    @Test func charactersAPathOrALinkCannotCarryBecomeUnderscores() {
        #expect(Attachment.fileName(for: "my photo (1).jpg", avoiding: []) == "my_photo__1_.jpg")
        #expect(Attachment.fileName(for: "a/b\\c:d*e?f\"g<h>i|j[k].png", avoiding: []) == "a_b_c_d_e_f_g_h_i_j_k_.png")
        #expect(Attachment.fileName(for: "tab\there.txt", avoiding: []) == "tab_here.txt")
        #expect(Attachment.fileName(for: "sale%20today#1.jpg", avoiding: []) == "sale_20today_1.jpg")
    }

    @Test func aLeadingDotIsReplacedAndAnEmptyNameIsCalledFile() {
        #expect(Attachment.fileName(for: ".hidden.jpg", avoiding: []) == "_hidden.jpg")
        #expect(Attachment.fileName(for: "", avoiding: []) == "file")
    }

    @Test func aNameTheFolderHasGetsTheNextFreeCounterBeforeTheExtension() {
        #expect(Attachment.fileName(for: "IMG.jpeg", avoiding: ["IMG.jpeg"]) == "IMG-2.jpeg")
        #expect(Attachment.fileName(for: "IMG.jpeg", avoiding: ["IMG.jpeg", "IMG-2.jpeg"]) == "IMG-3.jpeg")
        #expect(Attachment.fileName(for: "README", avoiding: ["README"]) == "README-2")
    }

    @Test func theLineLinksTheFileInTheFolderBesideTheNote() {
        #expect(Attachment.line(name: "IMG_0421.jpeg", folder: "2026-10-03T135812Z-a1b2") == "![IMG_0421.jpeg](2026-10-03T135812Z-a1b2/IMG_0421.jpeg)")
    }
}
