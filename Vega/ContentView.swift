import Foundation
import SwiftUI

struct ContentView: View {
    @State private var model: SignInModel
    @State private var diaryModel: DiaryScreenModel
    private let showsDiaryFixture: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
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

        showsDiaryFixture = fixtureMode != nil
        _model = State(
            initialValue: SignInModel(sessionCoordinator: sessionCoordinator)
        )
        if let fixtureMode {
            let diaryStore = FixtureDailyDiaryStore(mode: fixtureMode)
            _diaryModel = State(
                initialValue: DiaryScreenModel(
                    selectedDate: Date(timeIntervalSince1970: 1_785_888_000),
                    calendar: fixtureCalendar,
                    diaryFetcher: diaryStore,
                    diaryEntryDeleter: diaryStore,
                    diaryEntryUpdater: diaryStore,
                    ingredientSearcher: diaryStore,
                    diaryEntryCreator: diaryStore
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
                    diaryEntryCreator: diaryAPI
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
