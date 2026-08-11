import AuthenticationServices
import Foundation
import SwiftUI

struct ContentView: View {
    private static let preferredInstanceAddressKey = "preferred-instance-address"

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var model: SignInModel
    @State private var diaryModel: DiaryScreenModel
    @State private var isWebSigningIn = false
    private let showsDiaryFixture: Bool
    private let barcodeScannerMode: BarcodeScannerMode

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let showsMFAFixture = arguments.contains("-uiTestMFAFixture")
        let fixtureMode: DiaryFixtureMode?
        if arguments.contains("-uiTestBasicDiaryFixture") {
            fixtureMode = .basicLogging
        } else if arguments.contains("-uiTestPlannedDiaryFixture")
            || arguments.contains("-uiTestDiaryFixture")
        {
            fixtureMode = .plannedMeals
        } else {
            fixtureMode = nil
        }
        let sessionCoordinator = SessionCoordinator()
        let authenticatedClient = AuthenticatedAPIClient(sessionCoordinator: sessionCoordinator)
        var fixtureCalendar = Calendar(identifier: .gregorian)
        fixtureCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fixtureNow = Date(timeIntervalSince1970: 1_785_931_200)

        showsDiaryFixture = fixtureMode != nil
        if arguments.contains("-uiTestBarcodeScannerUnavailableFixture") {
            barcodeScannerMode = .unavailable(
                "Camera access is off. Allow it in Settings or enter the code manually."
            )
        } else if arguments.contains("-uiTestBarcodeScannerFixture"),
            let barcode = ProductBarcode("5901234123457")
        {
            barcodeScannerMode = .fixture(barcode)
        } else {
            barcodeScannerMode = .camera
        }
        let preferredInstanceAddress =
            UserDefaults.standard.string(forKey: Self.preferredInstanceAddressKey)
            ?? "https://wger.de"
        let signInModel = SignInModel(
            instanceAddress: preferredInstanceAddress,
            authenticationClient: showsMFAFixture
                ? MFAFixtureAuthenticationClient() : AllauthClient(),
            sessionCoordinator: sessionCoordinator
        )
        _model = State(initialValue: signInModel)
        if let fixtureMode {
            let diaryStore = FixtureDailyDiaryStore(mode: fixtureMode)
            _diaryModel = State(
                initialValue: DiaryScreenModel(
                    selectedDate: fixtureNow,
                    calendar: fixtureCalendar,
                    diaryFetcher: diaryStore,
                    diaryEntryDeleter: diaryStore,
                    diaryEntryUpdater: diaryStore,
                    ingredientSearcher: diaryStore,
                    diaryEntryCreator: diaryStore,
                    recentDiaryFetcher: diaryStore,
                    now: { fixtureNow }
                )
            )
        } else {
            let diaryAPI = DailyDiaryAPI(client: authenticatedClient)
            _diaryModel = State(
                initialValue: DiaryScreenModel(
                    diaryFetcher: diaryAPI,
                    diaryEntryDeleter: diaryAPI,
                    diaryEntryUpdater: diaryAPI,
                    ingredientSearcher: diaryAPI,
                    diaryEntryCreator: diaryAPI,
                    recentDiaryFetcher: diaryAPI
                )
            )
        }
    }

    var body: some View {
        NavigationStack {
            if showsDiaryFixture {
                DailyDiaryView(
                    model: diaryModel,
                    instanceName: "fixture.wger.local",
                    signOut: {}
                )
            } else if let account = model.connectedAccount {
                DailyDiaryView(
                    model: diaryModel,
                    instanceName: account.instance.url.host()
                        ?? account.instance.url.absoluteString,
                    signOut: signOut
                )
            } else if let challenge = model.pendingMFAChallenge {
                mfaForm(challenge: challenge)
            } else if model.isRestoringSession {
                ProgressView("Restoring session…")
            } else {
                signInForm
            }
        }
        .task {
            guard !showsDiaryFixture,
                !ProcessInfo.processInfo.arguments.contains("-skipSessionRestore")
            else {
                return
            }
            await model.restoreSession()
        }
        .onChange(of: model.instanceAddress) { _, instanceAddress in
            UserDefaults.standard.set(
                instanceAddress,
                forKey: Self.preferredInstanceAddressKey
            )
        }
        .environment(\.barcodeScannerMode, barcodeScannerMode)
    }

    private func mfaForm(challenge: MFAChallenge) -> some View {
        Form {
            if challenge.supportsCodeEntry {
                Section {
                    TextField("Verification code", text: $model.mfaCode)
                        .keyboardType(challenge.supportsRecoveryCodes ? .asciiCapable : .numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .submitLabel(.go)
                        .onSubmit(startMFAVerification)
                        .accessibilityIdentifier("mfa-code")
                } header: {
                    Text("Two-factor authentication")
                } footer: {
                    Text(challenge.codeEntryPrompt)
                }

                Section {
                    Button(action: startMFAVerification) {
                        HStack {
                            Spacer()
                            if model.isVerifyingMFA {
                                ProgressView()
                            } else {
                                Text("Verify")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!model.canVerifyMFA)
                    .accessibilityIdentifier("verify-mfa")
                }
            } else {
                Section {
                    Label("Passkey sign-in", systemImage: "person.badge.key")
                    Text(
                        "This instance only offered a passkey. Continue in the secure browser to use it."
                    )
                } footer: {
                    Text(
                        "The browser can also use social login or company SSO configured by your instance."
                    )
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if challenge.methods.contains("webauthn") {
                Section {
                    Label("Passkey detected", systemImage: "person.badge.key")
                    Button("Continue with passkey") {
                        startWebSignIn()
                    }
                    .disabled(model.isSigningIn || isWebSigningIn)
                    .accessibilityIdentifier("web-sign-in")
                }
            }

            Section {
                Button("Back to sign in", role: .cancel) {
                    model.cancelMFA()
                }
            }
        }
        .navigationTitle("Verify sign-in")
    }

    private var signInForm: some View {
        Form {
            Section {
                TextField("Instance URL", text: $model.instanceAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Username or email", text: $model.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(startSignIn)
            } header: {
                Text("Connect to wger")
            } footer: {
                Text("Your password is used only to sign in. The session is stored securely.")
            }

            if let errorMessage = model.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: startSignIn) {
                    HStack {
                        Spacer()
                        if model.isSigningIn {
                            ProgressView()
                        } else {
                            Text("Sign in")
                        }
                        Spacer()
                    }
                }
                .disabled(!model.canSignIn)
            }

            Section {
                Button("Sign in on the web", systemImage: "safari") {
                    startWebSignIn()
                }
                .disabled(model.isSigningIn || model.isRestoringSession || isWebSigningIn)
                .accessibilityIdentifier("web-sign-in")
            } footer: {
                Text("Use a passkey, social login, company SSO, or an existing web session.")
            }
        }
        .navigationTitle("Vega")
    }

    private func startSignIn() {
        Task { await model.signIn() }
    }

    private func startMFAVerification() {
        Task { await model.verifyMFA() }
    }

    private func startWebSignIn() {
        guard !isWebSigningIn else { return }
        isWebSigningIn = true
        Task {
            defer { isWebSigningIn = false }
            do {
                let request = try model.makeWebAuthenticationRequest()
                let callbackURL = try await webAuthenticationSession.authenticate(
                    using: request.url,
                    callback: .customScheme("wger"),
                    preferredBrowserSession: .shared,
                    additionalHeaderFields: [:]
                )
                await model.completeWebSignIn(request: request, callbackURL: callbackURL)
            } catch {
                let authenticationError = error as NSError
                guard
                    authenticationError.domain != ASWebAuthenticationSessionErrorDomain
                        || authenticationError.code
                            != ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
                else { return }
                model.reportWebSignInFailure(error)
            }
        }
    }

    private func signOut() {
        Task { await model.signOut() }
    }
}

extension MFAChallenge {
    fileprivate var supportsRecoveryCodes: Bool {
        methods.contains("recovery_codes")
    }

    fileprivate var supportsCodeEntry: Bool {
        methods.contains("totp") || supportsRecoveryCodes
    }

    fileprivate var codeEntryPrompt: String {
        if methods.contains("totp") && supportsRecoveryCodes {
            return "Enter the current code from your authenticator, or a recovery code."
        }
        if supportsRecoveryCodes {
            return "Enter one of your recovery codes. Each code can be used only once."
        }
        return "Enter the current code from your authenticator."
    }
}

private nonisolated struct MFAFixtureAuthenticationClient: AuthenticationClient {
    func signIn(
        instance: InstanceURL,
        username: String,
        password: String
    ) async throws -> AuthenticationSession {
        throw AuthenticationError.mfaRequired(
            MFAChallenge(
                sessionToken: "ui-test-mfa-session",
                methods: ["totp", "recovery_codes", "webauthn"]
            )
        )
    }

    func completeMFA(
        instance: InstanceURL,
        challenge: MFAChallenge,
        code: String
    ) async throws -> AuthenticationSession {
        AuthenticationSession(accessToken: "ui-test-access", refreshToken: "ui-test-refresh")
    }
}

#Preview {
    ContentView()
}
