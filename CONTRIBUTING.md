# Contributing to AgentMeter

Thank you for considering a contribution. AgentMeter is intentionally small, privacy-conscious, and approachable for hobbyists.

## Before starting

- Search existing issues before opening a new one.
- Use an issue to discuss large changes before investing significant time.
- Keep pull requests focused on one problem.
- Never include provider credentials, session cookies, account identifiers, or private logs.

## Local checks

Install the development environment and run the checks before submitting a pull request:

```bash
make setup
make lint
make test
make firmware
```

Hardware changes should state the exact board revision and describe how the behavior was tested. Screenshots or short recordings are welcome for display changes.

## Commit messages

Use short, descriptive commit messages written in the imperative mood, for example:

```text
Add stale-data indicator
Fix BLE reconnect timeout
Document macOS permissions
```

## Documentation

Update the relevant file under `docs/` whenever a change affects installation, configuration, hardware, protocol behavior, or the user interface.

By contributing, you agree that your contribution may be distributed under the MIT License.

