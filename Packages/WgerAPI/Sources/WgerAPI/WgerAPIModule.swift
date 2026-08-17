import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Namespace for handwritten helpers around the generated wger API.
public enum WgerAPIModule {
    /// Creates a generated client that authenticates every request with a JWT.
    public static func authenticatedClient(
        serverURL: URL,
        accessToken: String
    ) -> Client {
        Client(
            serverURL: serverURL,
            configuration: .init(dateTranscoder: WgerDateTranscoder()),
            transport: URLSessionTransport(),
            middlewares: [BearerAuthenticationMiddleware(accessToken: accessToken)]
        )
    }

    /// Fetches the short-lived credentials used by the PowerSync SDK.
    public static func powerSyncCredentials(
        serverURL: URL,
        accessToken: String
    ) async throws -> WgerPowerSyncCredentials {
        try await powerSyncCredentials(
            client: authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        )
    }

    static func powerSyncCredentials(client: Client) async throws -> WgerPowerSyncCredentials {
        let response = try await client.powersyncTokenRetrieve()
        switch response {
        case .ok(let response):
            let body = try response.body.json
            return WgerPowerSyncCredentials(token: body.token, endpoint: body.powersyncUrl)
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Uploads one local PowerSync mutation through wger's typed OpenAPI contract.
    public static func uploadPowerSyncData(
        serverURL: URL,
        accessToken: String,
        method: WgerPowerSyncUploadMethod,
        table: String,
        data: any Sendable
    ) async throws -> WgerPowerSyncUploadResult {
        let request = Components.Schemas.PowersyncUploadRequest(
            table: table,
            data: try OpenAPIValueContainer(unvalidatedValue: data)
        )
        return try await uploadPowerSyncData(
            client: authenticatedClient(serverURL: serverURL, accessToken: accessToken),
            method: method,
            request: request
        )
    }

    static func uploadPowerSyncData(
        client: Client,
        method: WgerPowerSyncUploadMethod,
        request: Components.Schemas.PowersyncUploadRequest
    ) async throws -> WgerPowerSyncUploadResult {
        switch method {
        case .put:
            switch try await client.uploadPowersyncDataUpdate(body: .json(request)) {
            case .ok(let response):
                return try uploadResult(from: response.body.json)
            case .forbidden:
                return .init(statusCode: 403)
            case .internalServerError:
                return .init(statusCode: 500)
            case .serviceUnavailable:
                return .init(statusCode: 503)
            case .undocumented(let statusCode, _):
                return .init(statusCode: statusCode)
            }
        case .patch:
            switch try await client.uploadPowersyncDataPartialUpdate(
                body: .json(
                    .init(table: request.table, data: request.data)
                )
            ) {
            case .ok(let response):
                return try uploadResult(from: response.body.json)
            case .forbidden:
                return .init(statusCode: 403)
            case .internalServerError:
                return .init(statusCode: 500)
            case .serviceUnavailable:
                return .init(statusCode: 503)
            case .undocumented(let statusCode, _):
                return .init(statusCode: statusCode)
            }
        case .delete:
            switch try await client.uploadPowersyncDataDestroy(body: .json(request)) {
            case .ok(let response):
                return try uploadResult(from: response.body.json)
            case .forbidden:
                return .init(statusCode: 403)
            case .internalServerError:
                return .init(statusCode: 500)
            case .serviceUnavailable:
                return .init(statusCode: 503)
            case .undocumented(let statusCode, _):
                return .init(statusCode: statusCode)
            }
        }
    }

    private static func uploadResult(
        from response: Components.Schemas.PowersyncUploadResponse
    ) -> WgerPowerSyncUploadResult {
        .init(
            statusCode: 200,
            error: response.error,
            details: response.details
        )
    }

    /// Proves that a token is accepted by requesting one authenticated resource.
    public static func nutritionPlanCount(
        serverURL: URL,
        accessToken: String
    ) async throws -> Int {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.nutritionplanList(query: .init(limit: 1))

        switch response {
        case .ok(let response):
            return try response.body.json.count
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Returns one page of the user's nutrition plans.
    public static func nutritionPlans(
        serverURL: URL,
        accessToken: String,
        limit: Int,
        offset: Int
    ) async throws -> Components.Schemas.PaginatedNutritionPlanList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.nutritionplanList(
            query: .init(limit: limit, offset: offset)
        )
        return try response.value()
    }

    /// Returns one page of the signed-in user's non-template workout routines.
    public static func routines(
        serverURL: URL,
        accessToken: String,
        limit: Int,
        offset: Int
    ) async throws -> Components.Schemas.PaginatedRoutineList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.routineList(
            query: .init(
                isTemplate: false,
                limit: limit,
                offset: offset,
                ordering: "-start,-created"
            )
        )
        return try response.value()
    }

    /// Returns the server-resolved workout sequence, including set targets.
    public static func workoutDayPlans(
        serverURL: URL,
        accessToken: String,
        routineID: Int
    ) async throws -> [Components.Schemas.WorkoutDayDataGymMode] {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.routineDateSequenceGymList(
            path: .init(id: routineID)
        )
        switch response {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Returns display metadata for the requested exercises.
    public static func exerciseInfo(
        serverURL: URL,
        accessToken: String,
        ids: [Int],
        languageCode: String = "en"
    ) async throws -> Components.Schemas.PaginatedExerciseInfoList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.exerciseinfoList(
            query: .init(
                idIn: ids,
                languageCode: languageCode,
                limit: ids.count
            )
        )
        return try response.value()
    }

    /// Returns one page of set logs for a routine on a calendar date.
    public static func workoutLogs(
        serverURL: URL,
        accessToken: String,
        routineID: Int,
        date: String,
        limit: Int,
        offset: Int
    ) async throws -> Components.Schemas.PaginatedWorkoutLogList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.workoutlogList(
            query: .init(
                dateDate: date,
                limit: limit,
                offset: offset,
                ordering: "date",
                routine: routineID
            )
        )
        return try response.value()
    }

    /// Returns one page of units accepted for workout weight values.
    public static func workoutWeightUnits(
        serverURL: URL,
        accessToken: String,
        limit: Int,
        offset: Int
    ) async throws -> Components.Schemas.PaginatedRoutineWeightUnitList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.settingWeightunitList(
            query: .init(limit: limit, offset: offset)
        )
        return try response.value()
    }

    /// Returns one page of units accepted for workout repetition values.
    public static func workoutRepetitionUnits(
        serverURL: URL,
        accessToken: String,
        limit: Int,
        offset: Int
    ) async throws -> Components.Schemas.PaginatedRepetitionUnitList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.settingRepetitionunitList(
            query: .init(limit: limit, offset: offset)
        )
        return try response.value()
    }

    /// Records one completed workout set.
    public static func createWorkoutLog(
        serverURL: URL,
        accessToken: String,
        log: Components.Schemas.WorkoutLogRequest
    ) async throws -> Components.Schemas.WorkoutLog {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.workoutlogCreate(body: .json(log))
        switch response {
        case .created(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Corrects repetitions and weight on a completed workout set.
    public static func updateWorkoutLog(
        serverURL: URL,
        accessToken: String,
        id: String,
        repetitions: String?,
        weight: String?,
        repetitionsUnit: Int?,
        weightUnit: Int?
    ) async throws -> Components.Schemas.WorkoutLog {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.workoutlogPartialUpdate(
            path: .init(id: id),
            body: .json(
                .init(
                    repetitionsUnit: repetitionsUnit,
                    repetitions: repetitions,
                    weightUnit: weightUnit,
                    weight: weight
                )
            )
        )
        switch response {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Deletes one completed workout set.
    public static func deleteWorkoutLog(
        serverURL: URL,
        accessToken: String,
        id: String
    ) async throws {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.workoutlogDestroy(path: .init(id: id))
        switch response {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Returns the nutrients supplied by the foods scheduled in one plan.
    public static func nutritionPlanValues(
        serverURL: URL,
        accessToken: String,
        planID: String
    ) async throws -> Components.Schemas.NutritionalValues {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.nutritionplanNutritionalValuesRetrieve(
            path: .init(id: planID)
        )
        switch response {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Returns one page of diary entries in a half-open time range.
    public static func nutritionDiary(
        serverURL: URL,
        accessToken: String,
        planID: String,
        from start: Date,
        to end: Date,
        limit: Int,
        offset: Int
    ) async throws -> Components.Schemas.PaginatedLogItemList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.nutritiondiaryList(
            query: .init(
                datetimeGte: start,
                datetimeLt: end,
                limit: limit,
                offset: offset,
                ordering: "datetime",
                plan: planID
            )
        )
        return try response.value()
    }

    /// Returns one page of meals belonging to a nutrition plan.
    public static func meals(
        serverURL: URL,
        accessToken: String,
        planID: String,
        limit: Int,
        offset: Int
    ) async throws -> Components.Schemas.PaginatedMealList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.mealList(
            query: .init(limit: limit, offset: offset, ordering: "order", plan: planID)
        )
        return try response.value()
    }

    /// Returns ingredient details for the requested numeric IDs.
    public static func ingredientInfo(
        serverURL: URL,
        accessToken: String,
        ids: [Int]
    ) async throws -> Components.Schemas.PaginatedIngredientInfoList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.ingredientinfoList(
            query: .init(idIn: ids, limit: ids.count)
        )
        return try response.value()
    }

    /// Searches the readable ingredient catalogue by name.
    public static func searchIngredientInfo(
        serverURL: URL,
        accessToken: String,
        query: String,
        limit: Int
    ) async throws -> Components.Schemas.PaginatedIngredientInfoList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.ingredientinfoList(
            query: .init(limit: limit, nameSearch: query)
        )
        return try response.value()
    }

    /// Returns one newest-first page of the signed-in user's weight history.
    public static func weightEntries(
        serverURL: URL,
        accessToken: String,
        limit: Int,
        offset: Int
    ) async throws -> Components.Schemas.PaginatedWeightEntryList {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.weightentryList(
            query: .init(limit: limit, offset: offset, ordering: "-date")
        )
        return try response.value()
    }

    /// Creates one body-weight measurement.
    public static func createWeightEntry(
        serverURL: URL,
        accessToken: String,
        date: Date,
        weight: String
    ) async throws -> Components.Schemas.WeightEntry {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.weightentryCreate(
            body: .json(.init(date: date, weight: weight))
        )
        switch response {
        case .created(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Replaces the editable fields of one body-weight measurement.
    public static func updateWeightEntry(
        serverURL: URL,
        accessToken: String,
        id: Int,
        date: Date,
        weight: String
    ) async throws -> Components.Schemas.WeightEntry {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.weightentryUpdate(
            path: .init(id: id),
            body: .json(.init(date: date, weight: weight))
        )
        switch response {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Deletes one body-weight measurement.
    public static func deleteWeightEntry(
        serverURL: URL,
        accessToken: String,
        id: Int
    ) async throws {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.weightentryDestroy(path: .init(id: id))
        switch response {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Creates one consumed ingredient in the nutrition diary.
    public static func createNutritionDiaryEntry(
        serverURL: URL,
        accessToken: String,
        entry: NutritionDiaryEntryCreate
    ) async throws {
        let url = serverURL.appendingPathComponent("api/v2/nutritiondiary/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(entry)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WgerAPIError.invalidResponse
        }
        guard response.statusCode == 201 else {
            throw WgerAPIError.unexpectedStatus(response.statusCode)
        }
    }

    /// Deletes one nutrition diary entry.
    public static func deleteNutritionDiaryEntry(
        serverURL: URL,
        accessToken: String,
        id: String
    ) async throws {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.nutritiondiaryDestroy(path: .init(id: id))

        switch response {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }

    /// Updates the editable fields of one nutrition diary entry.
    public static func updateNutritionDiaryEntry(
        serverURL: URL,
        accessToken: String,
        id: String,
        patch: NutritionDiaryEntryPatch
    ) async throws {
        try await patchNutritionDiaryEntry(
            serverURL: serverURL,
            accessToken: accessToken,
            id: id,
            body: patch
        )
    }

    private static func patchNutritionDiaryEntry<Body: Encodable>(
        serverURL: URL,
        accessToken: String,
        id: String,
        body: Body
    ) async throws {
        let url =
            serverURL
            .appendingPathComponent("api/v2/nutritiondiary")
            .appendingPathComponent(id)
            .appendingPathComponent("")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WgerAPIError.invalidResponse
        }
        guard response.statusCode == 200 else {
            throw WgerAPIError.unexpectedStatus(response.statusCode)
        }
    }
}

/// Accepts both ISO 8601 forms emitted by supported wger/Django versions.
struct WgerDateTranscoder: DateTranscoder {
    private let standard = ISO8601DateTranscoder()
    private let fractional = ISO8601DateTranscoder(options: [
        .withInternetDateTime, .withFractionalSeconds,
    ])

    func encode(_ date: Date) throws -> String {
        try standard.encode(date)
    }

    func decode(_ dateString: String) throws -> Date {
        do {
            return try fractional.decode(dateString)
        } catch {
            return try standard.decode(dateString)
        }
    }
}

public struct NutritionDiaryEntryCreate: Encodable, Equatable, Sendable {
    public let plan: String
    public let ingredient: Int
    public let amount: String
    public let weightUnit: Int?
    public let datetime: Date
    public let meal: String?

    public init(
        plan: String,
        ingredient: Int,
        amount: String,
        weightUnit: Int?,
        datetime: Date,
        meal: String?
    ) {
        self.plan = plan
        self.ingredient = ingredient
        self.amount = amount
        self.weightUnit = weightUnit
        self.datetime = datetime
        self.meal = meal
    }

    enum CodingKeys: String, CodingKey {
        case plan
        case ingredient
        case amount
        case weightUnit = "weight_unit"
        case datetime
        case meal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plan, forKey: .plan)
        try container.encode(ingredient, forKey: .ingredient)
        try container.encode(amount, forKey: .amount)
        if let weightUnit {
            try container.encode(weightUnit, forKey: .weightUnit)
        } else {
            try container.encodeNil(forKey: .weightUnit)
        }
        try container.encode(datetime, forKey: .datetime)
        if let meal {
            try container.encode(meal, forKey: .meal)
        } else {
            try container.encodeNil(forKey: .meal)
        }
    }
}

public struct NutritionDiaryEntryPatch: Encodable, Equatable, Sendable {
    public let amount: String
    public let weightUnit: Int?
    public let datetime: Date
    public let meal: String?

    public init(amount: String, weightUnit: Int?, datetime: Date, meal: String?) {
        self.amount = amount
        self.weightUnit = weightUnit
        self.datetime = datetime
        self.meal = meal
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case weightUnit = "weight_unit"
        case datetime
        case meal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount, forKey: .amount)
        if let weightUnit {
            try container.encode(weightUnit, forKey: .weightUnit)
        } else {
            try container.encodeNil(forKey: .weightUnit)
        }
        try container.encode(datetime, forKey: .datetime)
        if let meal {
            try container.encode(meal, forKey: .meal)
        } else {
            try container.encodeNil(forKey: .meal)
        }
    }
}

extension Operations.NutritionplanList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedNutritionPlanList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.RoutineList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedRoutineList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.NutritiondiaryList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedLogItemList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.MealList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedMealList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.IngredientinfoList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedIngredientInfoList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.ExerciseinfoList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedExerciseInfoList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.WorkoutlogList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedWorkoutLogList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.SettingWeightunitList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedRoutineWeightUnitList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.SettingRepetitionunitList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedRepetitionUnitList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

extension Operations.WeightentryList.Output {
    fileprivate func value() throws -> Components.Schemas.PaginatedWeightEntryList {
        switch self {
        case .ok(let response):
            return try response.body.json
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

/// Injects a bearer token into requests made by the generated wger client.
public struct BearerAuthenticationMiddleware: ClientMiddleware {
    private let accessToken: String

    public init(accessToken: String) {
        self.accessToken = accessToken
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next:
            @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (
                HTTPResponse, HTTPBody?
            )
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = "Bearer \(accessToken)"
        return try await next(request, body, baseURL)
    }
}

public struct WgerPowerSyncCredentials: Equatable, Sendable {
    public let token: String
    public let endpoint: String

    public init(token: String, endpoint: String) {
        self.token = token
        self.endpoint = endpoint
    }
}

public enum WgerPowerSyncUploadMethod: String, Equatable, Sendable {
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct WgerPowerSyncUploadResult: Equatable, Sendable {
    public let statusCode: Int
    public let error: String?
    public let details: String?

    public init(statusCode: Int, error: String? = nil, details: String? = nil) {
        self.statusCode = statusCode
        self.error = error
        self.details = details
    }
}

public enum WgerAPIError: Error, Equatable, Sendable {
    case unexpectedStatus(Int)
    case invalidResponse
}
