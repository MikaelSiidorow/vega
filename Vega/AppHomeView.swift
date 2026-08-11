import SwiftUI

struct AppHomeView: View {
    @Bindable var diaryModel: DiaryScreenModel
    @Bindable var weightModel: WeightHistoryModel
    let instanceName: String
    let signOut: () -> Void

    var body: some View {
        TabView {
            Tab("Diary", systemImage: "fork.knife") {
                NavigationStack {
                    DailyDiaryView(
                        model: diaryModel,
                        instanceName: instanceName,
                        signOut: signOut
                    )
                }
            }

            Tab("Weight", systemImage: "scalemass") {
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
