# Changelog

All notable changes are documented here. This project follows Semantic Versioning where practical.

## [Unreleased]

### Added

- QQ-backed one-shot DSH approval requests.
- Official QR onboarding that persists AppID, Secret, and the scanner's OpenID locally.
- Privacy check, GitHub Actions CI, community templates, architecture and troubleshooting docs.
- Windows source quick-start script.

### Security

- Private chat defaults to a fail-closed allowlist.
- Credentials and OpenIDs are kept outside the repository in `$DSH_HOME/.env`.
- Debug gateway bodies and QQ identifiers are redacted.

## [0.1.0] - 2026-08-16

- Initial community release derived from Tencent's MIT-licensed DSH QQ Bot plugin.
