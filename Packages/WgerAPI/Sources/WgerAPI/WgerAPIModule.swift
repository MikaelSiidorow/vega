import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

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
}
