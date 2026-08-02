# Hardware

## Recommended board

AgentMeter initially targets the [Waveshare ESP32-S3-Touch-AMOLED-2.16](https://www.waveshare.com/esp32-s3-touch-amoled-2.16.htm).

Required specification:

| Component | Specification |
| --- | --- |
| Processor | ESP32-S3R8, dual-core, up to 240 MHz |
| Display | 2.16-inch AMOLED, 480×480, CO5300 controller |
| Touch | Capacitive, CST9220 controller |
| Memory | 8 MB PSRAM and 16 MB flash |
| Wireless | 2.4 GHz Wi-Fi and Bluetooth 5 LE |
| Connection | USB Type-C with data support |
| Power | USB 5 V; optional 3.7 V LiPo through MX1.25 two-pin connector |

Choose the **ESP32-S3** 2.16-inch variant. Similar ESP32-C6 and 1.54-, 1.75-, 1.8-, and 2.06-inch products require different firmware.

## Bill of materials

### Required

| Quantity | Item | Notes |
| ---: | --- | --- |
| 1 | Waveshare ESP32-S3-Touch-AMOLED-2.16 | The no-battery version is recommended for the first build. |
| 1 | USB-C data cable | Use USB-C to USB-C or USB-A to USB-C for the computer. It must support data transfer. |
| 1 | Computer with Bluetooth LE | macOS is the first supported host. |

### Optional

| Quantity | Item | Purpose |
| ---: | --- | --- |
| 1 | Branded 5 V, 2 A USB power adapter | Permanent desk power after firmware installation |
| 1 | Small adjustable desktop stand | Better viewing angle during development |
| 4 | Small rubber feet | Prevent sliding and protect the enclosure |
| 1 | Official 3.7 V battery bundle | Portable operation; postpone until the USB-powered build is stable |

No separate Arduino, screen, Bluetooth module, breadboard, jumper wires, microSD card, or soldering equipment is required for the first version.

## Battery caution

The board uses a two-pin **MX1.25** battery connector. Connector shape does not guarantee correct polarity, and common JST-PH 2.0 batteries do not fit. Use the manufacturer's battery bundle if portable operation is required. Never connect a battery before checking voltage, connector, and polarity against the board documentation.

## Software libraries

The firmware scaffold pins these components in `firmware/platformio.ini`:

| Component | Purpose | License |
| --- | --- | --- |
| Espressif Arduino framework through pioarduino | ESP32 runtime | LGPL-2.1-or-later |
| LVGL | Display interface | MIT |
| ArduinoJson | Bounded JSON parsing | MIT |
| NimBLE-Arduino | Bluetooth LE transport | Apache-2.0 |
| Arduino_GFX | Display bus and graphics support | Apache-2.0 |
| XPowersLib | AXP2101 power management | MIT |
| SensorLib | Board sensor support | MIT |

Dependency notices will be reviewed and included before the first binary release.

## Arrival checklist

When the board arrives:

1. Photograph the package label, board revision, ports, and visible pin labels.
2. Check for shipping damage before connecting power.
3. Connect it with a known data-capable USB cable.
4. Record the serial port and confirm a basic firmware upload.
5. Test the display, touch, user button, and power management individually.
6. Run a 30-minute gradient/display test and watch for resets or visual corruption.

Do not install a battery during initial bring-up.

## Board bring-up reference

The firmware board layer follows the manufacturer's published pin map for the
ESP32-S3-Touch-AMOLED-2.16:

| Function | GPIO |
| --- | --- |
| CO5300 QSPI data 0–3 | 4, 5, 6, 7 |
| CO5300 chip select | 12 |
| CO5300 QSPI clock | 38 |
| CO5300 reset | 39 |
| Shared I2C SDA / SCL | 15 / 14 |
| CST9220 interrupt / reset | 11 / 40 |
| User button | 18, active low |

Primary sources:

- [Waveshare hardware documentation](https://docs.waveshare.com/ESP32-S3-Touch-AMOLED-2.16)
- [Waveshare schematic](https://files.waveshare.com/wiki/ESP32-S3-Touch-AMOLED-2.16/ESP32-S3-Touch-AMOLED-2.16-Schematic.pdf)
- [Waveshare Arduino examples](https://github.com/waveshareteam/ESP32-S3-Touch-AMOLED-2.16/tree/main/examples/arduino), reviewed at commit `713f8bdcc0fc2356ac22335ed4f381096e45ceea` (Apache-2.0)

The board layer uses two 38,400-byte LVGL partial buffers in external PSRAM.
The application uses the CST9220 touch controller, GPIO18 user button, AXP2101
power management, CO5300 display, and the ESP32-S3 BLE radio. The speaker is
connected through the ES8311 I2S codec, so audio is reserved for a separate
driver milestone rather than treated as a direct GPIO buzzer.

PlatformIO uses the `esp32-s3-devkitc1-n16r8` board profile. This exact profile
is important: it enables the unit's 16 MB quad flash and 8 MB octal PSRAM.
Using the generic no-PSRAM ESP32-S3 DevKit profile prevents the LVGL buffers
from being allocated even though the physical chip contains PSRAM.

### Flash and monitor

With the board connected over USB, find its serial port and run:

```bash
.venv/bin/pio device list
.venv/bin/pio run -d firmware --target upload --upload-port /dev/cu.usbmodemXXXX
.venv/bin/pio device monitor --port /dev/cu.usbmodemXXXX --baud 115200
```

Expected checks:

1. A dark AgentMeter waiting screen appears and includes the BLE name.
2. Serial output reports the AXP2101, CO5300, CST9220, PSRAM, BLE advertising,
   and a periodic heartbeat.
3. `agentmeter send` changes the waiting screen to the provider overview.
4. Tapping a provider opens its detail view; the back control returns.
5. A short GPIO18 press toggles overview/detail. A five-second hold clears BLE
   bonds and shows a confirmation banner.
6. Leave the dashboard running for 30 minutes and check that no resets,
   corruption, stuck pixels, excessive heat, or unexpected brightness occurs.

### Initial validation

The first development unit completed a 30-minute animated-display soak on
August 1, 2026. Serial telemetry reported 46,800 display flushes at an average
of 527 microseconds, with free heap steady at 188,520 bytes and minimum free
heap steady at 183,244 bytes. No resets, watchdogs, or firmware errors occurred.

AMOLED color and visual integrity, touch navigation, button behavior, alert
banners, and enclosure temperature remain manual checks because they require
observation of the physical unit.
