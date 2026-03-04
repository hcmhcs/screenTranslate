# Contributing to ScreenTranslate

Thanks for your interest in contributing!

## How to Contribute

1. **Open an issue first** — Before starting work, please open an issue to discuss the change. This helps avoid duplicate effort.
2. **Fork and branch** — Fork the repo and create a branch from `dev`.
3. **Keep changes focused** — One feature or fix per PR.
4. **Test your changes** — Make sure the app builds and runs correctly on macOS 15+.
5. **Submit a PR** — Open a pull request to the `dev` branch with a clear description.

## Development Setup

- **Xcode 16+** required
- **macOS 15+** (Sequoia)
- Open `ScreenTranslate.xcodeproj` and build

## Code Style

- Swift 6 with strict concurrency
- `@Observable` pattern (not ObservableObject)
- Default `@MainActor` isolation

## Reporting Bugs

Please use the [Bug Report](https://github.com/hcmhcs/screenTranslate/issues/new?template=bug_report.yml) template.

## License

By contributing, you agree that your contributions will be licensed under the [GPL v3](LICENSE).
