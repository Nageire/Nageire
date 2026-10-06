import Foundation
import Testing
@testable import Nageire

@MainActor
struct NageireAppTests {
    @Test func theAppStartedForTheTestsHoldsAModelOfItsOwn() {
        let model = NageireApp.makeModel()

        #expect(!model.isSignedIn)
        #expect(model.defaults != .standard)
    }
}
