import XCTest
@testable import YatseRemote

/// Kodi's add-ons hand back artwork hosted by whatever box the user runs — for
/// JellyCon that is `https://10.13.13.2:54406`, whose certificate is issued by a
/// home-lab CA the device has never been told to trust, so `URLSession` refused
/// the handshake and every tile drew its placeholder. `ArtworkSession` accepts a
/// certificate for a private address and nothing else; this pins that boundary,
/// because getting it wrong either leaves add-on art broken or stops validating
/// public hosts.
final class ArtworkSessionTests: XCTestCase {
    func testPrivateAddressesAreAccepted() {
        // The measured failing case: JellyCon's Jellyfin proxy on this setup.
        XCTAssertTrue(ArtworkSession.isLocal("10.13.13.2"))
        XCTAssertTrue(ArtworkSession.isLocal("10.0.0.129"))
        XCTAssertTrue(ArtworkSession.isLocal("127.0.0.1"))
        XCTAssertTrue(ArtworkSession.isLocal("192.168.10.156"))
        XCTAssertTrue(ArtworkSession.isLocal("172.16.0.9"))
        XCTAssertTrue(ArtworkSession.isLocal("172.31.255.254"))
        XCTAssertTrue(ArtworkSession.isLocal("localhost"))
        XCTAssertTrue(ArtworkSession.isLocal("kodi.local"))
    }

    func testPublicHostsStillHaveToValidate() {
        // PKC's artwork rides a real plex.direct certificate — it must keep being
        // checked, and nothing that resolves to the internet gets a free pass.
        XCTAssertFalse(ArtworkSession.isLocal("10-0-0-129.ea9fa151a2af4395aca7d4191dedd86d.plex.direct"))
        XCTAssertFalse(ArtworkSession.isLocal("i.ytimg.com"))
        XCTAssertFalse(ArtworkSession.isLocal("image.tmdb.org"))
        XCTAssertFalse(ArtworkSession.isLocal("8.8.8.8"))
        XCTAssertFalse(ArtworkSession.isLocal("172.32.0.1"))   // just outside 172.16/12
        XCTAssertFalse(ArtworkSession.isLocal("192.169.0.1"))
        XCTAssertFalse(ArtworkSession.isLocal("11.0.0.1"))
        // Not an address at all, so no exception can be justified for it.
        XCTAssertFalse(ArtworkSession.isLocal("10.13.13.300"))
        XCTAssertFalse(ArtworkSession.isLocal(""))
    }
}
