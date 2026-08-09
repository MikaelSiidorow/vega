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
            transport: URLSessionTransport(),
            middlewares: [BearerAuthenticationMiddleware(accessToken: accessToken)]
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

public enum WgerAPIError: Error, Equatable, Sendable {
    case unexpectedStatus(Int)
    case invalidResponse
}
