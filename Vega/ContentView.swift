import SwiftUI

struct ContentView: View {
    @State private var model = SignInModel()

    var body: some View {
        NavigationStack {
            if let account = model.connectedAccount {
                connectedView(account)
            } else {
                signInForm
            }
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
                Text("Credentials are used only to sign in and are not stored yet.")
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

    private func connectedView(_ account: ConnectedAccount) -> some View {
        ContentUnavailableView {
            Label("Connected", systemImage: "checkmark.circle.fill")
        } description: {
            VStack(spacing: 8) {
                Text(account.instance.url.host() ?? account.instance.url.absoluteString)
                Text(planSummary(account.nutritionPlanCount))
            }
        } actions: {
            Button("Sign out", role: .destructive, action: model.signOut)
        }
        .navigationTitle("Vega")
    }

    private func planSummary(_ count: Int) -> String {
        count == 1 ? "1 nutrition plan found" : "\(count) nutrition plans found"
    }

    private func startSignIn() {
        Task { await model.signIn() }
    }
}

#Preview {
    ContentView()
}
