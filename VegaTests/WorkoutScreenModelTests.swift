import Foundation
import Testing

@testable import Vega

@MainActor
struct WorkoutScreenModelTests {
    @Test
    func loadsDashboardAndRefreshesAfterMutation() async {
        let store = FixtureWorkoutStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let model = WorkoutScreenModel(
            dashboardFetcher: store,
            setCreator: store,
            setUpdater: store,
            setDeleter: store,
            calendar: calendar,
            now: { FixtureWorkoutStore.now }
        )

        await model.load()
        let day = model.dashboard?.today
        let plan = day?.exercises.last
        #expect(model.dashboard?.logs.count == 2)
        guard let day, let plan else {
            Issue.record("Expected fixture workout")
            return
        }

        #expect(
            await model.createSet(
                for: plan,
                day: day,
                input: WorkoutSetInput(repetitions: "12", weight: "47.5")
            )
        )
        #expect(model.dashboard?.logs.count == 3)
        await model.deleteSet(id: "fixture-log-3")
        #expect(model.dashboard?.logs.count == 2)
    }
}
