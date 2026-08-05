import Foundation
import SwiftUI

struct ContentView: View {
    @State private var model: SignInModel
    @State private var diaryModel: DiaryScreenModel
    private let showsDiaryFixture: Bool

    init() {
        let showsDiaryFixture = ProcessInfo.processInfo.arguments.contains("-uiTestDiaryFixture")
        let sessionCoordinator = SessionCoordinator()
        let authenticatedClient = AuthenticatedAPIClient(sessionCoordinator: sessionCoordinator)
        var fixtureCalendar = Calendar(identifier: .gregorian)
        fixtureCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        self.showsDiaryFixture = showsDiaryFixture
        _model = State(
            initialValue: SignInModel(sessionCoordinator: sessionCoordinator)
        )
        _diaryModel = State(
            initialValue: showsDiaryFixture
                ? DiaryScreenModel(
                    selectedDate: Date(timeIntervalSince1970: 1_785_888_000),
                    calendar: fixtureCalendar,
                    diaryFetcher: FixtureDailyDiaryFetcher()
                )
                : DiaryScreenModel(
                    diaryFetcher: DailyDiaryAPI(client: authenticatedClient)
                )
        )
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
        }
        .navigationTitle("Vega")
    }

    private func startSignIn() {
        Task { await model.signIn() }
    }

    private func signOut() {
        Task { await model.signOut() }
    }
}

#Preview {
    ContentView()
}
