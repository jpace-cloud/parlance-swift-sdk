# Changelog

All notable changes to ParlanceSDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-22

### Added

- Initial release of `ParlanceSDK`, the Swift client for the Parlance API.
- `ParlanceClient` with a user-supplied API key (`Authorization: Bearer`) and a
  default base URL of `https://api.parlancelabs.net`.
- Projects: `listProjects`.
- Contracts: `getContracts`, `getContractDetail`, `createContract`,
  `updateContract`, `deleteContract`.
- Glossary: `getGlossary`, `createGlossaryTerm`, `updateGlossaryTerm`,
  `deleteGlossaryTerm`.
- Standards: `getStandards`.
- Audit results: `pushAuditResults`.
- Validation: `validate`.
- Connectivity check: `testConnection`.
- Four-level `AuditSeverity` (`info`, `warning`, `error`, `critical`) with
  `suggestedFix`, `pageUrl`, and `score` fields on `AuditResultInput`.
- Typed `ParlanceError` (`unauthorized`, `api`, `noData`, `transport`,
  `decoding`).
- `{ data, error, meta }` response-envelope decoding.
- URLProtocol-stubbed unit test coverage for all `ParlanceClient` methods.
- GitHub Actions test workflow.

[0.1.0]: https://github.com/jpace-cloud/parlance-swift-sdk/releases/tag/0.1.0
