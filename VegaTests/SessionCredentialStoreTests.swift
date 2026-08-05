import Foundation
import Testing

@testable import Vega

#if canImport(Security)
    @Suite(.serialized)
    struct SessionCredentialStoreTests {
        @Test
        func savesReplacesAndClearsSession() async throws {
            let identifier = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: identifier))
            let store = KeychainSessionCredentialStore(
                service: "VegaTests.\(identifier)",
                instanceAddressKey: "instance",
                defaults: defaults
            )

            try await store.save(
                StoredSession(
                    instanceAddress: "https://first.example/",
                    refreshToken: "first-token"
                )
            )
            #expect(
                try await store.load()
                    == StoredSession(
                        instanceAddress: "https://first.example/",
                        refreshToken: "first-token"
                    )
            )

            try await store.save(
                StoredSession(
                    instanceAddress: "https://second.example/",
                    refreshToken: "rotated-token"
                )
            )
            #expect(
                try await store.load()
                    == StoredSession(
                        instanceAddress: "https://second.example/",
                        refreshToken: "rotated-token"
                    )
            )

            try await store.clear()
            #expect(try await store.load() == nil)
            defaults.removePersistentDomain(forName: identifier)
        }
    }
#endif
