# Roadmap

AgentMeter is in early development. Milestones are ordered to produce a reliable, understandable hobby project before adding optional features.

## 0. Repository foundation — complete

- Public project structure and MIT license
- Host and firmware toolchain scaffolds
- Architecture, hardware, setup, configuration, protocol, and contribution guides
- Safe device schema and fixture
- Automated host and firmware checks

## 1. Hardware bring-up — in progress

- Confirm the exact board revision and USB upload process — complete
- Initialize the AMOLED and render a test pattern — complete
- Verify touch, the user button, and power management — complete
- Verify audio, IMU, and RTC — planned as separate drivers
- Record verified pins and board notes — complete
- Run a 30-minute stability test — complete

## 2. Host data source — complete

- Launch CodexBar securely on loopback — complete
- Validate dashboard schema version 1 — complete
- Normalize Codex, Claude, and Gemini snapshots — complete
- Prove that identity and credentials never enter device payloads — complete
- Complete a live-provider acceptance run with Codex, Claude, and Gemini — complete

## 3. Communication

- Implement Bluetooth discovery, framing, acknowledgement, retry, and reconnect
- Implement USB serial fallback
- Add a `doctor` command for permissions and connection problems
- Complete repeated-send and forced-disconnect tests

## 4. Display interface

- Create overview and provider-detail screens
- Add reset countdowns and progress indicators
- Add waiting, stale, disconnected, and error states
- Add touch navigation and physical-button fallback
- Add dimming, screen-off, and pixel-shift protection

## 5. Alerts and packaging

- Add deduplicated 75% and 90% alerts
- Add optional short device sounds
- Package the host for straightforward macOS installation
- Publish firmware binaries and a photographed assembly guide
- Complete an independent setup test from the documentation

## Later ideas

- Linux and Windows host packages
- Additional display boards and enclosure files
- Historical sparklines and local trend storage
- Desktop notifications
- Multiple paired displays
- Secure over-the-air firmware updates
