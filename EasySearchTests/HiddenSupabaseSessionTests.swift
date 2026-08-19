import Foundation
import XCTest
@testable import EasySearch

final class HiddenSupabaseSessionTests: XCTestCase {
    func testSignOutDuringRefreshCannotRestoreSession() async throws {
        let userID = UUID()
        let original = makeSession(prefix: "a", userID: userID, expiresIn: 30)
        let refreshed = makeSession(prefix: "a-refreshed", userID: userID, expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        let refresh = Task { try await service.restoreSessionIfPossible() }
        await transport.waitForRequestCount(1)

        await service.signOut()
        await transport.succeedRequest(at: 0, data: try authResponse(for: refreshed))

        do {
            _ = try await refresh.value
            XCTFail("A refresh invalidated by sign-out must not succeed")
        } catch {
            // Cancellation/supersession is the expected result.
        }

        let restored = try await service.restoreSessionIfPossible()
        XCTAssertNil(restored)
        XCTAssertNil(store.load())
        XCTAssertEqual(store.clearCount, 1)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testConcurrentNearExpiryCallersShareOneRefresh() async throws {
        let userID = UUID()
        let original = makeSession(prefix: "a", userID: userID, expiresIn: 30)
        let refreshed = makeSession(prefix: "a-refreshed", userID: userID, expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        async let first = service.restoreSessionIfPossible()
        async let second = service.restoreSessionIfPossible()

        await transport.waitForRequestCount(1)
        let requestCountBeforeResponse = await transport.requestCount
        XCTAssertEqual(requestCountBeforeResponse, 1)
        await transport.succeedRequest(at: 0, data: try authResponse(for: refreshed))

        let (firstResult, secondResult) = try await (first, second)
        XCTAssertEqual(firstResult?.accessToken, refreshed.accessToken)
        XCTAssertEqual(secondResult?.accessToken, refreshed.accessToken)
        let finalRequestCount = await transport.requestCount
        XCTAssertEqual(finalRequestCount, 1)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.load()?.refreshToken, refreshed.refreshToken)
    }

    func testReplacingUserACannotBeOverwrittenByLateRefresh() async throws {
        let userA = UUID()
        let userB = UUID()
        let originalA = makeSession(prefix: "a", userID: userA, expiresIn: 30)
        let refreshedA = makeSession(prefix: "a-refreshed", userID: userA, expiresIn: 3_600)
        let signedInB = makeSession(prefix: "b", userID: userB, expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: originalA)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        let refreshA = Task { try await service.restoreSessionIfPossible() }
        await transport.waitForRequestCount(1)

        let signInB = Task { try await service.signIn(email: "b@example.com", password: "password") }
        await transport.waitForRequestCount(2)
        await transport.succeedRequest(at: 1, data: try authResponse(for: signedInB))

        let signInResult = try await signInB.value
        XCTAssertEqual(signInResult.userID, userB)

        await transport.succeedRequest(at: 0, data: try authResponse(for: refreshedA))
        do {
            _ = try await refreshA.value
            XCTFail("User A refresh must be superseded by user B sign-in")
        } catch {
            // The older refresh must be rejected, even if the server completed it.
        }

        let current = try await service.restoreSessionIfPossible()
        XCTAssertEqual(current?.userID, userB)
        XCTAssertEqual(current?.accessToken, signedInB.accessToken)
        XCTAssertEqual(store.load()?.userID, userB)
        XCTAssertEqual(store.saveCount, 1)
    }

    func testTransientRefreshFailureRetainsStoredSession() async throws {
        let original = makeSession(prefix: "a", userID: UUID(), expiresIn: 30)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        let refresh = Task { try await service.restoreSessionIfPossible() }
        await transport.waitForRequestCount(1)
        await transport.failRequest(at: 0, error: URLError(.notConnectedToInternet))

        do {
            _ = try await refresh.value
            XCTFail("The transport failure should be surfaced")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }

        XCTAssertEqual(store.load()?.accessToken, original.accessToken)
        XCTAssertEqual(store.clearCount, 0)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testServerFailureDuringRefreshRetainsStoredSession() async throws {
        let original = makeSession(prefix: "a", userID: UUID(), expiresIn: 30)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        let refresh = Task { try await service.restoreSessionIfPossible() }
        await transport.waitForRequestCount(1)
        let payload = try JSONSerialization.data(withJSONObject: [
            "message": "Auth service temporarily unavailable"
        ])
        await transport.succeedRequest(at: 0, data: payload, statusCode: 503)

        do {
            _ = try await refresh.value
            XCTFail("The server failure should be surfaced")
        } catch {
            XCTAssertEqual((error as NSError).code, 503)
        }

        XCTAssertEqual(store.load()?.accessToken, original.accessToken)
        XCTAssertEqual(store.clearCount, 0)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testDefinitiveRefreshInvalidationClearsStoredSession() async throws {
        let original = makeSession(prefix: "a", userID: UUID(), expiresIn: 30)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        let refresh = Task { try await service.restoreSessionIfPossible() }
        await transport.waitForRequestCount(1)
        let payload = try JSONSerialization.data(withJSONObject: [
            "code": "refresh_token_not_found",
            "message": "Refresh token not found"
        ])
        await transport.succeedRequest(at: 0, data: payload, statusCode: 400)

        do {
            _ = try await refresh.value
            XCTFail("A revoked refresh token should fail")
        } catch {
            XCTAssertEqual((error as NSError).code, 400)
            XCTAssertTrue(error.isHiddenSupabaseAuthFailure)
        }

        XCTAssertNil(store.load())
        XCTAssertEqual(store.clearCount, 1)
    }

    func testMalformedRefreshResponseDoesNotPoisonLaterRetry() async throws {
        let userID = UUID()
        let original = makeSession(prefix: "a", userID: userID, expiresIn: 30)
        let refreshed = makeSession(prefix: "a-recovered", userID: userID, expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        let malformedRefresh = Task { try await service.restoreSessionIfPossible() }
        await transport.waitForRequestCount(1)
        await transport.succeedRequest(at: 0, data: Data("{".utf8))

        do {
            _ = try await malformedRefresh.value
            XCTFail("Malformed refresh JSON must fail")
        } catch {
            XCTAssertEqual(store.load()?.accessToken, original.accessToken)
        }

        let retry = Task { try await service.restoreSessionIfPossible() }
        await transport.waitForRequestCount(2)
        await transport.succeedRequest(at: 1, data: try authResponse(for: refreshed))

        let recovered = try await retry.value
        XCTAssertEqual(recovered?.accessToken, refreshed.accessToken)
        XCTAssertEqual(store.load()?.refreshToken, refreshed.refreshToken)
        let finalRequestCount = await transport.requestCount
        XCTAssertEqual(finalRequestCount, 2)
    }

    func testConfirmationRequiredSignUpClearsPreviousSession() async throws {
        let original = makeSession(prefix: "a", userID: UUID(), expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        let signUp = Task {
            try await service.signUp(email: "new@example.com", password: "password")
        }
        await transport.waitForRequestCount(1)
        await transport.succeedRequest(
            at: 0,
            data: Data(#"{"user":{"id":"00000000-0000-0000-0000-000000000001"}}"#.utf8)
        )

        let outcome = try await signUp.value
        guard case .confirmationRequired = outcome else {
            return XCTFail("Sign-up without tokens must require confirmation")
        }

        let restored = try await service.restoreSessionIfPossible()
        XCTAssertNil(restored)
        XCTAssertNil(store.load())
        XCTAssertEqual(store.clearCount, 1)
    }

    func testUnauthorizedRESTRequestRefreshesAndRetriesOnce() async throws {
        let userID = UUID()
        let original = makeSession(prefix: "a", userID: userID, expiresIn: 3_600)
        let refreshed = makeSession(prefix: "a-refreshed", userID: userID, expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        let fetch = Task { try await service.fetchFavorites(expectedUserID: userID) }
        await transport.waitForRequestCount(1)
        await transport.succeedRequest(
            at: 0,
            data: Data(#"{"message":"JWT expired"}"#.utf8),
            statusCode: 401
        )

        await transport.waitForRequestCount(2)
        await transport.succeedRequest(at: 1, data: try authResponse(for: refreshed))

        await transport.waitForRequestCount(3)
        await transport.succeedRequest(at: 2, data: Data("[]".utf8))

        let favorites = try await fetch.value
        XCTAssertTrue(favorites.isEmpty)
        XCTAssertEqual(store.load()?.accessToken, refreshed.accessToken)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.clearCount, 0)
        let finalRequestCount = await transport.requestCount
        XCTAssertEqual(finalRequestCount, 3)
    }

    func testForbiddenRESTResponseDoesNotDiscardValidSession() async throws {
        let userID = UUID()
        let original = makeSession(prefix: "a", userID: userID, expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: original)
        let configuration = testConfiguration
        let service = HiddenSupabaseService(
            configuration: configuration,
            sessionStore: store,
            transport: { request in
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 403,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (Data(#"{"message":"RLS denied"}"#.utf8), response)
            }
        )

        do {
            _ = try await service.fetchFavorites(expectedUserID: userID)
            XCTFail("The forbidden response should be surfaced")
        } catch {
            XCTAssertFalse(error.isHiddenSupabaseAuthFailure)
        }

        XCTAssertEqual(store.load()?.accessToken, original.accessToken)
        XCTAssertEqual(store.clearCount, 0)
    }

    func testMutationForDifferentExpectedUserNeverReachesTransport() async throws {
        let signedInUser = UUID()
        let expectedUser = UUID()
        let original = makeSession(prefix: "signed-in", userID: signedInUser, expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)

        do {
            try await service.deleteFavorite(
                movieID: "https://example.com/movie",
                expectedUserID: expectedUser
            )
            XCTFail("A mutation must not use a different account's session")
        } catch {
            XCTAssertEqual((error as NSError).code, -8)
        }

        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(store.load()?.userID, signedInUser)
    }

    func testUnknownTrainingUnitFailsClosedInsteadOfCreatingTombstone() async throws {
        let userID = UUID()
        let original = makeSession(prefix: "training", userID: userID, expiresIn: 3_600)
        let store = InMemorySupabaseSessionStore(session: original)
        let transport = ControlledSupabaseTransport()
        let service = makeService(store: store, transport: transport)
        let responseData = try JSONSerialization.data(withJSONObject: [[
            "day_id": "2026-08-15",
            "day_start": "2026-08-15T00:00:00.000Z",
            "note": "future payload",
            "updated_at": "2026-08-15T09:00:00.000Z",
            "lines": [[
                "id": UUID().uuidString,
                "exercise_id": "future-exercise",
                "exercise_name": "未来动作",
                "amount": 1,
                "unit": "future-unit",
                "created_at": "2026-08-15T08:00:00.000Z"
            ]]
        ]])

        let fetch = Task { try await service.fetchTrainingDays(expectedUserID: userID) }
        await transport.waitForRequestCount(1)
        await transport.succeedRequest(at: 0, data: responseData)

        do {
            _ = try await fetch.value
            XCTFail("Unknown remote units must fail the collection instead of dropping lines")
        } catch DecodingError.dataCorrupted(let context) {
            XCTAssertTrue(context.debugDescription.contains("Unsupported training unit"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(store.load()?.userID, original.userID)
    }

    private var testConfiguration: HiddenSupabaseConfiguration {
        HiddenSupabaseConfiguration(
            baseURL: URL(string: "https://project.supabase.co")!,
            publishableKey: "test-publishable-key",
            schema: "easysearch"
        )
    }

    private func makeService(
        store: InMemorySupabaseSessionStore,
        transport: ControlledSupabaseTransport
    ) -> HiddenSupabaseService {
        HiddenSupabaseService(
            configuration: testConfiguration,
            sessionStore: store,
            transport: { request in
                try await transport.send(request)
            }
        )
    }

    private func makeSession(
        prefix: String,
        userID: UUID,
        expiresIn: TimeInterval
    ) -> HiddenSupabaseSession {
        HiddenSupabaseSession(
            accessToken: "\(prefix)-access",
            refreshToken: "\(prefix)-refresh",
            expiresAt: Date().addingTimeInterval(expiresIn),
            userID: userID,
            email: "\(prefix)@example.com"
        )
    }

    private func authResponse(for session: HiddenSupabaseSession) throws -> Data {
        var user: [String: Any] = [:]
        if let userID = session.userID {
            user["id"] = userID.uuidString
        }
        if let email = session.email {
            user["email"] = email
        }

        return try JSONSerialization.data(withJSONObject: [
            "access_token": session.accessToken,
            "refresh_token": session.refreshToken,
            "expires_at": session.expiresAt.timeIntervalSince1970,
            "user": user
        ])
    }
}

private final class InMemorySupabaseSessionStore: HiddenSupabaseSessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var session: HiddenSupabaseSession?
    private var storedSaveCount = 0
    private var storedClearCount = 0

    init(session: HiddenSupabaseSession?) {
        self.session = session
    }

    var saveCount: Int {
        lock.withLock { storedSaveCount }
    }

    var clearCount: Int {
        lock.withLock { storedClearCount }
    }

    func load() -> HiddenSupabaseSession? {
        lock.withLock { session }
    }

    func save(_ session: HiddenSupabaseSession) throws {
        lock.withLock {
            self.session = session
            storedSaveCount += 1
        }
    }

    func clear() {
        lock.withLock {
            session = nil
            storedClearCount += 1
        }
    }
}

private actor ControlledSupabaseTransport {
    private struct PendingRequest {
        let request: URLRequest
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
    }

    private var pendingRequests: [Int: PendingRequest] = [:]
    private var requestCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var requestCount = 0

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let index = requestCount
            requestCount += 1
            pendingRequests[index] = PendingRequest(request: request, continuation: continuation)
            resumeSatisfiedWaiters()
        }
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        if requestCount >= expectedCount { return }

        await withCheckedContinuation { continuation in
            requestCountWaiters.append((expectedCount, continuation))
        }
    }

    func succeedRequest(at index: Int, data: Data, statusCode: Int = 200) {
        guard let pending = pendingRequests.removeValue(forKey: index),
              let url = pending.request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            return
        }

        pending.continuation.resume(returning: (data, response))
    }

    func failRequest(at index: Int, error: Error) {
        guard let pending = pendingRequests.removeValue(forKey: index) else { return }
        pending.continuation.resume(throwing: error)
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in requestCountWaiters {
            if requestCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        requestCountWaiters = remaining
    }
}
