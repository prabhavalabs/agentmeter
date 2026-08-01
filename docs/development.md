# Development

## Working areas

- `host/` contains the Python desktop application and tests.
- `firmware/` contains the PlatformIO project for the display.
- `schemas/` defines the shared contract.
- `fixtures/` contains safe, synthetic samples used by both sides.
- `docs/` explains decisions and user-facing workflows.

Keep provider-specific authentication and parsing on the host. Keep the firmware provider-neutral.

## Host workflow

```bash
make setup
make lint
make test
```

Ruff provides formatting and static checks. Pytest runs from `host/tests/`.
The CodexBar tests use a local fake server process, so the complete automated test
suite does not require provider accounts or a CodexBar installation. A manual live
acceptance run uses `agentmeter snapshot --pretty`.

## Firmware workflow

```bash
make firmware
.venv/bin/pio run -d firmware --target upload
.venv/bin/pio device monitor -d firmware
```

Board-specific pin definitions and display initialization live under
`firmware/src/boards/`. Keep new board support isolated there and expose it
through the small interface in the board header.

## Contract changes

Any device-message change must update:

1. The JSON Schema under `schemas/`
2. At least one safe fixture under `fixtures/`
3. Host validation tests
4. Firmware parser tests
5. `docs/protocol.md`

Breaking changes require a new `schemaVersion`; do not silently change the meaning of an existing field.

Never add raw CodexBar dashboard responses as fixtures. Tests must use synthetic
identity, billing, status, and error values and assert that these fields do not
reach the device document.

## Pull requests

Keep changes focused and explain their effect on users or contributors. Hardware-dependent changes should state the exact board revision and how they were tested. Never attach raw provider responses or logs containing personal data.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the complete checklist.
