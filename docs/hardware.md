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
5. Test the display, touch, buttons, audio, and power management individually.
6. Run a 30-minute gradient/display test and watch for resets or visual corruption.

Do not install a battery during initial bring-up.
