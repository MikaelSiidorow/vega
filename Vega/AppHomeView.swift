import SwiftUI

struct AppHomeView: View {
    private enum Destination: Hashable {
        case diary
        case workouts
        case progress
    }

    @Bindable var diaryModel: DiaryScreenModel
    @Bindable var weightModel: WeightHistoryModel
    let instanceName: String
    let signOut: () -> Void
    @State private var selection = Destination.diary

    var body: some View {
        TabView(selection: $selection) {
            Tab("Diary", systemImage: "fork.knife", value: .diary) {
                NavigationStack {
                    DailyDiaryView(
                        model: diaryModel,
                        instanceName: instanceName,
                        signOut: signOut
                    )
                }
            }

            Tab("Workouts", systemImage: "dumbbell.fill", value: .workouts) {
                NavigationStack {
                    WorkoutsPlaceholderView(instanceName: instanceName, signOut: signOut)
                }
            }

            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) {
                NavigationStack {
                    WeightHistoryView(
                        model: weightModel,
                        instanceName: instanceName,
                        signOut: signOut
                    )
                }
            }
        }
    }
}

private struct WorkoutsPlaceholderView: View {
    let instanceName: String
    let signOut: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No workouts yet", systemImage: "dumbbell.fill")
        } description: {
            Text("Your workout plans and today's training will appear here.")
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Text(instanceName)
                    Button("Sign out", role: .destructive, action: signOut)
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
        }
        .accessibilityIdentifier("workouts-placeholder")
    }
}
