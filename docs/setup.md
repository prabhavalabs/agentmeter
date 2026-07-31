# Setup

The first development target is macOS 14 or later. Linux instructions will be added after the Bluetooth path is validated on macOS.

## Prerequisites

- Git
- Python 3.11 or later
- A data-capable USB-C cable
- Waveshare ESP32-S3-Touch-AMOLED-2.16 for firmware testing

`make setup` installs PlatformIO inside the project's virtual environment. If you only want the firmware toolchain, install PlatformIO with its official installer or an isolated Python tool such as `pipx`:

```bash
pipx install platformio
```

## Clone and prepare the host

```bash
git clone https://github.com/prabhavalabs/agentmeter.git
cd agentmeter
make setup
```

Verify the scaffold:

```bash
.venv/bin/agentmeter --version
.venv/bin/agentmeter doctor
make lint
make test
```

The `doctor` command reports optional components that have not yet been installed. A missing CodexBar installation is expected until the data-source phase is implemented.

## Build the firmware

```bash
make firmware
```

When the board is connected, upload and open the serial monitor:

```bash
.venv/bin/pio run -d firmware --target upload
.venv/bin/pio device monitor -d firmware
```

The initial scaffold prints its name and version over USB serial. Display initialization will be added during hardware bring-up.

## Configuration

Copy `config.example.toml` to the location shown by:

```bash
.venv/bin/agentmeter doctor
```

The example documents the planned settings. Data collection and device connection are intentionally not enabled in the initial scaffold.
