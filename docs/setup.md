# Setup

The first development target is macOS 14 or later. Linux instructions will be added after the Bluetooth path is validated on macOS.

## Prerequisites

- Git
- Python 3.11 or later
- A recent CodexBar CLI with `codexbar serve`
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

The `doctor` command requires the Python libraries, CodexBar command, and a valid
AgentMeter configuration. Install the CodexBar CLI from **Preferences → Advanced →
Install CLI** in the macOS app, then verify it with:

```bash
codexbar --version
codexbar serve --help
```

## Build the firmware

```bash
make firmware
```

When the board is connected, upload and open the serial monitor:

```bash
.venv/bin/pio run -d firmware --target upload
.venv/bin/pio device monitor -d firmware
```

After flashing, the screen shows the AgentMeter hardware diagnostic. Confirm
the moving display test, tap coordinates, and button-controlled brightness.
The serial monitor reports peripheral detection, PSRAM capacity, display timing,
and a five-second heartbeat. See [Hardware](hardware.md#board-bring-up-reference)
for the expected results.

## Configuration

Copy `config.example.toml` to the location shown by:

```bash
.venv/bin/agentmeter doctor
```

After copying the file, verify the secure local data path:

```bash
.venv/bin/agentmeter doctor
.venv/bin/agentmeter snapshot --pretty
```

Snapshot collection is implemented. Bluetooth device delivery remains disabled
until the communication milestone. See [Host data source](host.md) for behavior,
privacy rules, and troubleshooting.
