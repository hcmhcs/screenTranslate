# Contributing to ScreenTranslate

Thanks for your interest in contributing!

## How to Contribute

1. **Open an issue first** — Before starting work, please open an issue to discuss the change. This helps avoid duplicate effort.
2. **Fork and branch** — Fork the repo and create a branch from `dev`.
3. **Keep changes focused** — One feature or fix per PR.
4. **Test your changes** — Make sure the app builds and runs correctly on macOS 15+, and the tests pass (`Cmd + U` in Xcode).
5. **Submit a PR** — Open a pull request to the `dev` branch with a clear description.

## Development Setup

- **Xcode 26+** required (the project uses Swift 6.2's default `@MainActor` isolation)
- **macOS 15+** (Sequoia)
- Open `ScreenTranslate.xcodeproj` and build

## Code Style

- Swift 5 language mode with complete concurrency checking (Swift 6 toolchain) — please don't add new warnings
- `@Observable` pattern (not ObservableObject)
- Default `@MainActor` isolation

## How Contributions Are Credited

- **Merged pull requests** keep you as the commit author.
- **Reworked ideas** — Sometimes we rebuild a PR instead of merging it, to fit the app's architecture or privacy rules. You're still credited in the changelog, release notes, and README, and added as a co-author on the commit that ships it.
- **Suggestions and bug reports** that lead to a change are credited in the changelog.

## Beta Features

Bigger new features may ship first as a beta — off by default, under Settings → Advanced → Beta Features — so we can gather feedback before making them a regular feature.

## AI-Assisted Contributions

AI tools are welcome. Please mention it in your PR, and make sure you understand and have tested the code you submit.

## Reporting Bugs

Please use the [Bug Report](https://github.com/hcmhcs/screenTranslate/issues/new?template=bug_report.yml) template.

## License

By contributing, you agree that your contributions will be licensed under the [GPL v3](LICENSE).
