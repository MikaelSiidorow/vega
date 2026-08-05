// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "WgerAPI",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "WgerAPI", targets: ["WgerAPI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-openapi-generator",
            exact: "1.13.0"
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-runtime",
            exact: "1.12.0"
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-urlsession",
            exact: "1.3.0"
        ),
        .package(
            url: "https://github.com/apple/swift-http-types",
            exact: "1.6.0"
        ),
    ],
    targets: [
        .target(
            name: "WgerAPI",
            dependencies: [
                .product(
                    name: "OpenAPIRuntime",
                    package: "swift-openapi-runtime"
                ),
                .product(
                    name: "OpenAPIURLSession",
                    package: "swift-openapi-urlsession"
                ),
                .product(
                    name: "HTTPTypes",
                    package: "swift-http-types"
                ),
            ],
            exclude: ["server-openapi.json"],
            plugins: [
                .plugin(
                    name: "OpenAPIGenerator",
                    package: "swift-openapi-generator"
                )
            ]
        ),
        .testTarget(
            name: "WgerAPITests",
            dependencies: [
                "WgerAPI",
                .product(
                    name: "OpenAPIRuntime",
                    package: "swift-openapi-runtime"
                ),
                .product(
                    name: "HTTPTypes",
                    package: "swift-http-types"
                ),
            ]
        ),
    ]
)
