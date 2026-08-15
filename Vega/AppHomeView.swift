import SwiftUI

struct AppHomeView: View {
    private enum Destination: Hashable {
        case diary
        case workouts
        case progress
    }

    @Bindable var diaryModel: DiaryScreenModel
    @Bindable var workoutModel: WorkoutScreenModel
    @Bindable var weightModel: WeightHistoryModel
    let syncModel: SyncStatusModel?
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
                        syncModel: syncModel,
                        signOut: signOut
                    )
                }
            }

            Tab("Workouts", systemImage: "dumbbell.fill", value: .workouts) {
                NavigationStack {
                    WorkoutsView(
                        model: workoutModel,
                        instanceName: instanceName,
                        syncModel: syncModel,
                        signOut: signOut
                    )
                }
            }

            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) {
                NavigationStack {
                    WeightHistoryView(
                        model: weightModel,
                        instanceName: instanceName,
                        syncModel: syncModel,
                        signOut: signOut
                    )
                }
            }
        }
        .task { await syncModel?.monitor() }
    }
}
