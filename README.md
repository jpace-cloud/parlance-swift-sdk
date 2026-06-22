# parlance-swift-sdk

Swift Package Manager library — the shared Swift client SDK for the [Parlance](https://parlancelabs.net) API.

This is the Swift counterpart to the TypeScript `@parlance/sdk`. Consumed by `parlance-xcode` and `parlance-native-auditor`.

## Module name

`ParlanceSDK` (distinct from `ParlanceKit` used internally by the Xcode extension).

## Platforms

- macOS 14+
- iOS 17+
- visionOS 1+

## Installation

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jpace-cloud/parlance-swift-sdk.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["ParlanceSDK"]
    ),
]
```

## Quick start

```swift
import ParlanceSDK

let client = ParlanceClient(
    apiKey: "pk_live_…",
    clientName: "xcode-extension/1.0.0"
)

// Validate connectivity
try await client.testConnection()

// List projects
let projects = try await client.listProjects()

// Get contracts (summary list)
let summaries = try await client.getContracts(projectId: projects[0].id)

// Get full contract detail
let contract = try await client.getContractDetail(
    projectId: projects[0].id,
    contractId: summaries[0].id
)

// Push audit results
let input = AuditResultInput(results: [
    AuditResultItem(
        ruleId: "wcag-1.1.1",
        severity: .error,
        message: "Image is missing an accessibility label",
        filePath: "Sources/Views/HomeView.swift"
    )
])
let result = try await client.pushAuditResults(projectId: projects[0].id, input: input)
print("Inserted \(result.inserted) findings")
```

## Error handling

All methods throw ``ParlanceError``:

```swift
do {
    let projects = try await client.listProjects()
} catch ParlanceError.unauthorized {
    // Invalid API key
} catch ParlanceError.api(let status, let message) {
    // API returned an error (non-401)
} catch ParlanceError.noData {
    // Response contained no data
} catch ParlanceError.transport(let error) {
    // Network-level failure
} catch ParlanceError.decoding(let error) {
    // Could not decode response body
}
```

## License

Copyright (c) 2026 Parlance Labs. All rights reserved. See [LICENSE.txt](LICENSE.txt).
