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

## Firmware workflow

```bash
make firmware
.venv/bin/pio run -d firmware --target upload
.venv/bin/pio device monitor -d firmware
```

Board-specific pin definitions and display initialization should remain under a dedicated board-support directory once hardware bring-up begins.

## Contract changes

Any device-message change must update:

1. The JSON Schema under `schemas/`
2. At least one safe fixture under `fixtures/`
3. Host validation tests
4. Firmware parser tests
5. `docs/protocol.md`

Breaking changes require a new `schemaVersion`; do not silently change the meaning of an existing field.

## Pull requests

Keep changes focused and explain their effect on users or contributors. Hardware-dependent changes should state the exact board revision and how they were tested. Never attach raw provider responses or logs containing personal data.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the complete checklist.
