# ESP32 Device Management Protocol Implementation Plan

**Goal:** Add a backward-compatible, encrypted, bidirectional management protocol that exposes
device information, honest power telemetry, and revisioned display settings to the host.

**Architecture:** Keep snapshot UUIDs `0002`/`0003` unchanged. Add encrypted request and event
characteristics `0004`/`0005`, reuse bounded eight-byte fragmentation, and route management
requests through a small device controller outside BLE callbacks. Move all display preferences
into one validated, versioned state whose confirmed revision is shared by touchscreen and host.

**Tech stack:** C++17, ArduinoJson 7.4.3, NimBLE-Arduino 2.5.0, Preferences/NVS, XPowersLib 0.2.7,
PlatformIO native Unity tests, Waveshare ESP32-S3-Touch-AMOLED-2.16.

## Global constraints

- Existing schema-v1 snapshots, ACK bytes, UUIDs, and USB serial fallback remain compatible.
- Management payloads are at most 2048 bytes; snapshot payloads remain at most 4096 bytes.
- Require encryption for request, event, snapshot, and ACK characteristics.
- Never report estimated current draw. Use nullable capability-gated telemetry.
- Reject a settings patch before changing active state when validation, revision, or persistence
  fails.
- Keep all parsing and serialization bounded; do not allocate from BLE callbacks.
- Device settings remain usable without a connected Mac.
- Add no provider credentials, identity, prompts, source code, or raw upstream responses.
- Run native tests and a complete ESP32 build after every task.

## File map

| File | Responsibility |
| --- | --- |
| `schemas/device-management-v1.schema.json` | Language-independent management envelope contract |
| `fixtures/device-management-*.json` | Valid information, telemetry, settings, and patch examples |
| `firmware/include/management_model.h` | Bounded device information, telemetry, settings, patch types |
| `firmware/src/management_model.cpp` | Validation, patch application, equality, provider ordering |
| `firmware/include/management_protocol.h` | Request parser and response/event encoder interfaces |
| `firmware/src/management_protocol.cpp` | ArduinoJson management codec |
| `firmware/include/settings_store.h` | Versioned settings load/save/migration API |
| `firmware/src/settings_store.cpp` | NVS blob persistence and legacy-key migration |
| `firmware/include/device_controller.h` | Management command orchestration interface |
| `firmware/src/device_controller.cpp` | Revisions, telemetry, command results, deferred actions |
| `firmware/include/transport.h` | Snapshot and management transport callback contract |
| `firmware/src/transport_ble.cpp` | New GATT characteristics, queues, fragmentation, notifications |
| `firmware/src/boards/waveshare_amoled_216/board.*` | Capability-gated PMIC telemetry |
| `firmware/src/ui.*` | Apply remote settings and publish touchscreen changes |
| `firmware/src/main.cpp` | Wire controller, transport, board, and UI |
| `firmware/test/test_native/test_management*.cpp` | Management, migration, framing, and revision tests |

---

### Task 1: Define the management schema and bounded settings model

**Files:**

- Create: `schemas/device-management-v1.schema.json`
- Create: `fixtures/device-management-state-v1.json`
- Create: `fixtures/device-management-patch-v1.json`
- Create: `firmware/include/management_model.h`
- Create: `firmware/src/management_model.cpp`
- Create: `firmware/test/test_native/test_management_model.cpp`
- Modify: `firmware/include/settings_model.h`
- Modify: `firmware/src/settings_model.cpp`
- Modify: `firmware/test/test_native/test_main.cpp`
- Modify: `firmware/platformio.ini`

**Interfaces:**

- Produces:
  `bool validate_device_settings(const DeviceSettings&, const DashboardSnapshot*)`
- Produces:
  `ManagementStatus apply_settings_patch(const SettingsPatch&, const DashboardSnapshot*,
  DeviceSettings&)`
- Produces:
  `uint8_t ordered_visible_provider_indices(const DashboardSnapshot&, const DeviceSettings&,
  std::array<uint8_t, kMaximumProviders>&)`
- Produces: `bool set_provider_order(DeviceSettings&, const char* const*, uint8_t)`
- Consumed by Tasks 2, 3, and 5.

- [ ] **Step 1: Add failing model tests**

Create tests that prove defaults, range validation, provider-order stability, unknown-provider
append behaviour, at-least-one-visible enforcement, and selective patches:

```cpp
void test_settings_patch_is_selective_and_preserves_revision() {
  DeviceSettings current{};
  current.revision = 8;
  SettingsPatch patch{};
  patch.has_always_on = true;
  patch.always_on = true;

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(ManagementStatus::Ok),
      static_cast<uint8_t>(apply_settings_patch(patch, nullptr, current)));
  TEST_ASSERT_TRUE(current.always_on);
  TEST_ASSERT_FALSE(current.full_view);
  TEST_ASSERT_EQUAL_UINT32(8, current.revision);
}

void test_ordered_visible_providers_appends_unknown_ids() {
  DashboardSnapshot snapshot = make_management_snapshot("codex", "claude", "cursor");
  DeviceSettings settings{};
  const char* order[] = {"claude", "codex"};
  TEST_ASSERT_TRUE(set_provider_order(settings, order, 2));
  std::array<uint8_t, kMaximumProviders> indices{};

  TEST_ASSERT_EQUAL_UINT8(
      3, ordered_visible_provider_indices(snapshot, settings, indices));
  TEST_ASSERT_EQUAL_UINT8(1, indices[0]);
  TEST_ASSERT_EQUAL_UINT8(0, indices[1]);
  TEST_ASSERT_EQUAL_UINT8(2, indices[2]);
}
```

Register `run_management_model_tests()` from the existing Unity `main()`.

- [ ] **Step 2: Run the native suite and verify the new symbols fail to compile**

```bash
.venv/bin/pio test -d firmware -e native
```

Expected: compilation fails because `DeviceSettings`, `SettingsPatch`, and the new functions do
not exist.

- [ ] **Step 3: Implement the bounded types and validation**

Define the public model with exact defaults and nullable telemetry flags:

```cpp
inline constexpr uint8_t kManagementSchemaVersion = 1;
inline constexpr size_t kMaximumManagementBytes = 2048;

enum class ManagementStatus : uint8_t {
  Ok = 0,
  MalformedFrame = 1,
  TooLarge = 2,
  InvalidJson = 3,
  UnsupportedSchema = 4,
  InvalidRequest = 5,
  RevisionConflict = 6,
  UnsupportedCommand = 7,
  PersistenceFailed = 8,
};

struct ProviderIdList {
  std::array<std::array<char, kDeviceTextBytes>, kMaximumProviders> values{};
  uint8_t count = 0;
};

struct DeviceSettings {
  uint32_t revision = 0;
  bool always_on = false;
  bool full_view = false;
  uint8_t rotation_seconds = 3;
  uint8_t brightness_percent = 55;
  uint32_t dim_after_seconds = 300;
  uint32_t screen_off_after_seconds = 1800;
  std::array<uint8_t, 3> alert_thresholds{75, 90, 0};
  uint8_t alert_threshold_count = 2;
  bool sound_enabled = false;
  ProviderIdList hidden_provider_ids{};
  ProviderIdList provider_order{};
};

struct SettingsPatch {
  uint32_t base_revision = 0;
  bool has_always_on = false;
  bool always_on = false;
  bool has_full_view = false;
  bool full_view = false;
  bool has_rotation_seconds = false;
  uint8_t rotation_seconds = 3;
  bool has_brightness_percent = false;
  uint8_t brightness_percent = 55;
  bool has_dim_after_seconds = false;
  uint32_t dim_after_seconds = 300;
  bool has_screen_off_after_seconds = false;
  uint32_t screen_off_after_seconds = 1800;
  bool has_alert_thresholds = false;
  std::array<uint8_t, 3> alert_thresholds{};
  uint8_t alert_threshold_count = 0;
  bool has_sound_enabled = false;
  bool sound_enabled = false;
  bool has_hidden_provider_ids = false;
  ProviderIdList hidden_provider_ids{};
  bool has_provider_order = false;
  ProviderIdList provider_order{};
};

enum class PowerSource : uint8_t { Unknown, Usb, Battery };

struct DeviceInformation {
  std::array<char, kDeviceTextBytes> model{};
  std::array<char, kDeviceTextBytes> name{};
  std::array<char, 16> firmware_version{};
  std::array<char, 16> hardware_revision{};
  uint8_t snapshot_schema_version = 1;
  uint8_t management_schema_version = 1;
  bool supports_settings = true;
  bool supports_identify = true;
  bool supports_restart = true;
  bool supports_forget = true;
  bool supports_brightness = true;
  bool supports_battery = false;
  bool supports_vbus_voltage = false;
  bool supports_input_current = false;
};

struct DeviceTelemetry {
  uint32_t uptime_seconds = 0;
  uint32_t free_heap_bytes = 0;
  uint32_t minimum_free_heap_bytes = 0;
  bool display_on = true;
  bool display_dimmed = false;
  uint8_t brightness_percent = 55;
  PowerSource power_source = PowerSource::Unknown;
  bool usb_present = false;
  bool battery_present = false;
  bool has_charging = false;
  bool charging = false;
  bool has_battery_voltage = false;
  uint16_t battery_voltage_mv = 0;
  bool has_battery_percent = false;
  uint8_t battery_percent = 0;
  bool has_vbus_voltage = false;
  uint16_t vbus_voltage_mv = 0;
  bool has_input_current = false;
  uint16_t input_current_ma = 0;
  bool has_board_temperature = false;
  float board_temperature_c = 0.0F;
};

struct DeviceState {
  DeviceInformation information{};
  DeviceTelemetry telemetry{};
  DeviceSettings settings{};
};
```

Use these exact bounds: rotation 3–60 seconds, brightness 1–100, dim 30–3600 seconds, screen-off
60–86400 seconds and greater than or equal to dim, one to three strictly increasing thresholds
from 1–100, and unique provider IDs matching `[a-z0-9_-]{1,23}`.

Replace `DashboardPreferences` uses with `DeviceSettings`. Preserve the old visibility helpers as
thin calls into the new model until all UI call sites compile.

- [ ] **Step 4: Add JSON Schema and fixtures that match the C++ names**

The schema must accept a request envelope shaped as:

```json
{
  "schemaVersion": 1,
  "requestId": 17,
  "type": "settings.patch",
  "payload": {"baseRevision": 8, "alwaysOn": true}
}
```

Set `additionalProperties: false` on the envelope and settings patch, define all numeric bounds,
and cap every provider array at eight unique IDs. The state fixture must include device info,
capabilities, telemetry with `batteryPresent: false`, and the full confirmed settings state.

- [ ] **Step 5: Run model tests and the firmware build**

```bash
.venv/bin/pio test -d firmware -e native
.venv/bin/pio run -d firmware
```

Expected: both pass; current dashboard behaviour remains unchanged.

- [ ] **Step 6: Commit the model contract**

```bash
git add schemas/device-management-v1.schema.json fixtures/device-management-*.json \
  firmware/include/management_model.h firmware/src/management_model.cpp \
  firmware/include/settings_model.h firmware/src/settings_model.cpp \
  firmware/test/test_native/test_management_model.cpp \
  firmware/test/test_native/test_main.cpp firmware/platformio.ini
git commit -m "feat(firmware): define device management model"
```

---

### Task 2: Add versioned settings persistence and legacy migration

**Files:**

- Create: `firmware/include/settings_codec.h`
- Create: `firmware/src/settings_codec.cpp`
- Create: `firmware/test/test_native/test_settings_codec.cpp`
- Modify: `firmware/include/settings_store.h`
- Modify: `firmware/src/settings_store.cpp`
- Modify: `firmware/test/test_native/test_main.cpp`
- Modify: `firmware/platformio.ini`

**Interfaces:**

- Produces: `bool encode_settings_blob(const DeviceSettings&, SettingsBlob&)`
- Produces: `SettingsDecodeStatus decode_settings_blob(const uint8_t*, size_t, DeviceSettings&)`
- Produces: `SettingsLoadResult load_device_settings(DeviceSettings&)`
- Produces: `bool save_device_settings(const DeviceSettings&)`
- Consumed by the device controller in Task 5.

- [ ] **Step 1: Write failing codec and migration tests**

```cpp
void test_settings_blob_round_trip_preserves_revision_and_order() {
  DeviceSettings input{};
  input.revision = 42;
  input.always_on = true;
  const char* order[] = {"claude", "codex"};
  TEST_ASSERT_TRUE(set_provider_order(input, order, 2));
  SettingsBlob blob{};
  DeviceSettings decoded{};

  TEST_ASSERT_TRUE(encode_settings_blob(input, blob));
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(SettingsDecodeStatus::Ok),
      static_cast<uint8_t>(
          decode_settings_blob(blob.bytes.data(), blob.length, decoded)));
  TEST_ASSERT_TRUE(device_settings_equal(input, decoded));
}

void test_settings_blob_rejects_changed_crc_without_mutating_output() {
  DeviceSettings original{};
  SettingsBlob blob{};
  TEST_ASSERT_TRUE(encode_settings_blob(original, blob));
  blob.bytes[blob.length - 1] ^= 0xFF;
  DeviceSettings output{};
  output.revision = 99;

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(SettingsDecodeStatus::InvalidChecksum),
      static_cast<uint8_t>(
          decode_settings_blob(blob.bytes.data(), blob.length, output)));
  TEST_ASSERT_EQUAL_UINT32(99, output.revision);
}
```

Add a pure legacy-decoding test using a `LegacySettings` value so migration logic can be verified
in the native environment without Arduino `Preferences`.

- [ ] **Step 2: Run the native suite and verify failure**

```bash
.venv/bin/pio test -d firmware -e native
```

Expected: compilation fails for the missing codec types.

- [ ] **Step 3: Implement a fixed, checksummed settings blob**

Use a byte encoding independent of compiler struct padding:

```text
bytes 0..3    magic "AMST"
byte 4        blob version = 1
bytes 5..8    little-endian revision
bytes 9..N    bounded settings fields and length-prefixed provider IDs
last 4 bytes  CRC32 of every preceding byte
```

`decode_settings_blob` must decode into a candidate, call `validate_device_settings`, and assign
the output only after checksum and validation succeed. Keep the blob under 512 bytes.

- [ ] **Step 4: Replace separate NVS writes with one atomic blob**

Use NVS key `settingsV1`. `load_device_settings` first tries the blob. When absent, read current
keys `alwaysOn`, `fullView`, `rotateSec`, and `hidden`, construct a valid `DeviceSettings` with
revision 1, save the blob once, and retain the old keys for rollback. Invalid blobs return safe
defaults without rewriting flash in a boot loop.

Expose:

```cpp
enum class SettingsLoadResult : uint8_t { Loaded, Migrated, Defaults, StorageError };
SettingsLoadResult load_device_settings(DeviceSettings& output);
bool save_device_settings(const DeviceSettings& settings);
```

- [ ] **Step 5: Run persistence tests and both firmware gates**

```bash
.venv/bin/pio test -d firmware -e native
.venv/bin/pio run -d firmware
```

Expected: codec tests pass and the ESP32 build resolves `Preferences` only in the board target.

- [ ] **Step 6: Commit persistence**

```bash
git add firmware/include/settings_codec.h firmware/src/settings_codec.cpp \
  firmware/include/settings_store.h firmware/src/settings_store.cpp \
  firmware/test/test_native/test_settings_codec.cpp \
  firmware/test/test_native/test_main.cpp firmware/platformio.ini
git commit -m "feat(firmware): persist revisioned device settings"
```

---

### Task 3: Implement management request parsing and response encoding

**Files:**

- Create: `firmware/include/management_protocol.h`
- Create: `firmware/src/management_protocol.cpp`
- Create: `firmware/test/test_native/test_management_protocol.cpp`
- Modify: `firmware/include/protocol.h`
- Modify: `firmware/src/protocol.cpp`
- Modify: `firmware/test/test_native/test_main.cpp`
- Modify: `firmware/platformio.ini`

**Interfaces:**

- Produces: `ManagementStatus parse_management_request(const uint8_t*, size_t,
  ManagementRequest&)`
- Produces: `size_t encode_management_result(const ManagementResult&, uint8_t*, size_t)`
- Produces: generic `FragmentReassembler::push(...)` for snapshot type `0x01` and management type
  `0x02`.
- Consumed by BLE transport and controller in Task 5.

- [ ] **Step 1: Add failing parser, encoder, and frame tests**

Test every command: `device.get`, `telemetry.get`, `settings.get`, `settings.patch`,
`device.identify`, `device.restart`, and `device.forget`. Include unsupported schema, unknown type,
missing request ID, invalid provider ID, oversized payload, out-of-order fragment, and request ID
correlation.

```cpp
void test_parse_settings_patch_captures_revision_and_fields() {
  constexpr char payload[] =
      R"({"schemaVersion":1,"requestId":17,"type":"settings.patch",)"
      R"("payload":{"baseRevision":8,"alwaysOn":true}})";
  ManagementRequest request{};

  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(ManagementStatus::Ok),
      static_cast<uint8_t>(parse_management_request(
          reinterpret_cast<const uint8_t*>(payload), std::strlen(payload),
          request)));
  TEST_ASSERT_EQUAL_UINT32(17, request.request_id);
  TEST_ASSERT_EQUAL(ManagementCommand::SettingsPatch, request.command);
  TEST_ASSERT_EQUAL_UINT32(8, request.settings_patch.base_revision);
  TEST_ASSERT_TRUE(request.settings_patch.has_always_on);
}
```

- [ ] **Step 2: Run the native suite and verify failure**

```bash
.venv/bin/pio test -d firmware -e native
```

- [ ] **Step 3: Implement the command codec with candidate assignment**

Define:

```cpp
enum class ManagementCommand : uint8_t {
  DeviceGet,
  TelemetryGet,
  SettingsGet,
  SettingsPatch,
  DeviceIdentify,
  DeviceRestart,
  DeviceForget,
};

struct ManagementRequest {
  uint32_t request_id = 0;
  ManagementCommand command = ManagementCommand::DeviceGet;
  SettingsPatch settings_patch{};
};

struct ManagementResult {
  uint32_t request_id = 0;
  ManagementCommand command = ManagementCommand::DeviceGet;
  ManagementStatus status = ManagementStatus::Ok;
  bool has_device_state = false;
  DeviceState device_state{};
};
```

Use a 2048-byte ArduinoJson document, reject unknown envelope and patch fields, and never assign
the request output until the complete candidate validates. Results use:

```json
{"schemaVersion":1,"requestId":17,"type":"settings.result","status":"ok","payload":{}}
```

Errors use stable codes `invalidRequest`, `revisionConflict`, `unsupportedCommand`, and
`persistenceFailed`; keep human-readable UI copy on the Mac.

- [ ] **Step 4: Generalize reassembly without changing snapshot semantics**

Add frame constants to `protocol.h`:

```cpp
inline constexpr uint8_t kSnapshotMessageType = 0x01;
inline constexpr uint8_t kManagementRequestMessageType = 0x02;
inline constexpr uint8_t kManagementResultMessageType = 0x82;
inline constexpr uint8_t kDeviceEventMessageType = 0x83;
```

The generic reassembler returns bytes, message ID, and message type. Keep the existing
`Reassembler::push(..., DashboardSnapshot&)` wrapper so all existing snapshot tests stay intact.
Add a management reassembler capped at 2048 bytes and the same two-second expiry.

- [ ] **Step 5: Run protocol tests, JSON fixture validation, and firmware build**

```bash
.venv/bin/pytest host/tests/test_schema.py -v
.venv/bin/pio test -d firmware -e native
.venv/bin/pio run -d firmware
```

- [ ] **Step 6: Commit the codec**

```bash
git add firmware/include/management_protocol.h firmware/src/management_protocol.cpp \
  firmware/include/protocol.h firmware/src/protocol.cpp \
  firmware/test/test_native/test_management_protocol.cpp \
  firmware/test/test_native/test_main.cpp firmware/platformio.ini
git commit -m "feat(firmware): add management message codec"
```

---

### Task 4: Expose capability-gated board telemetry

**Files:**

- Modify: `firmware/src/boards/waveshare_amoled_216/board.h`
- Modify: `firmware/src/boards/waveshare_amoled_216/board.cpp`
- Modify: `firmware/include/management_model.h`
- Modify: `firmware/src/management_protocol.cpp`
- Modify: `firmware/test/test_native/test_management_protocol.cpp`

**Interfaces:**

- Produces: `BoardTelemetry board_read_telemetry()`
- Produces: `void board_set_brightness_percent(uint8_t)`
- Consumed by the device controller in Task 5.

- [ ] **Step 1: Add failing serialization tests for USB-only and battery states**

```cpp
void test_device_state_encodes_usb_without_fabricating_battery() {
  DeviceState state = make_device_state();
  state.telemetry.power_source = PowerSource::Usb;
  state.telemetry.usb_present = true;
  state.telemetry.battery_present = false;
  std::array<uint8_t, kMaximumManagementBytes> output{};

  const size_t length = encode_device_state_event(state, output.data(), output.size());
  JsonDocument document;
  deserializeJson(document, output.data(), length);
  TEST_ASSERT_EQUAL_STRING("usb", document["payload"]["telemetry"]["powerSource"]);
  TEST_ASSERT_FALSE(document["payload"]["telemetry"]["batteryPresent"]);
  TEST_ASSERT_TRUE(document["payload"]["telemetry"]["batteryPercent"].isNull());
  TEST_ASSERT_TRUE(document["payload"]["telemetry"]["inputCurrentMa"].isNull());
}
```

- [ ] **Step 2: Run the native suite and verify the telemetry fields fail**

```bash
.venv/bin/pio test -d firmware -e native
```

- [ ] **Step 3: Implement the board telemetry adapter**

Add:

```cpp
struct BoardTelemetry {
  bool pmu_available = false;
  bool usb_present = false;
  bool battery_present = false;
  bool charging_available = false;
  bool charging = false;
  bool battery_voltage_available = false;
  uint16_t battery_voltage_mv = 0;
  bool battery_percent_available = false;
  uint8_t battery_percent = 0;
  bool vbus_voltage_available = false;
  uint16_t vbus_voltage_mv = 0;
};
```

When the AXP2101 initialized, use `isVbusGood()`, `isBatteryConnect()`, `isCharging()`,
`getBattVoltage()`, `getBatteryPercent()`, and `getVbusVoltage()`. Only call battery methods when a
battery is connected, and publish battery percentage only when the returned value is within
0–100. Enable VBUS voltage measurement during board initialization before reading it. Do not
expose `getVbusCurrentLimit()` as consumption; it is a configured limit, not a measurement.

- [ ] **Step 4: Apply brightness through one percent-based function**

Clamp 1–100 percent and convert once to the CO5300 0–255 value. Track the last applied percent for
telemetry. Screen-off may still write raw zero through a private helper, but confirmed settings
retain the configured nonzero brightness.

- [ ] **Step 5: Run the native suite and board build**

```bash
.venv/bin/pio test -d firmware -e native
.venv/bin/pio run -d firmware
```

- [ ] **Step 6: Commit telemetry**

```bash
git add firmware/src/boards/waveshare_amoled_216/board.h \
  firmware/src/boards/waveshare_amoled_216/board.cpp \
  firmware/include/management_model.h firmware/src/management_protocol.cpp \
  firmware/test/test_native/test_management_protocol.cpp
git commit -m "feat(firmware): expose honest device telemetry"
```

---

### Task 5: Wire management GATT, controller, and touchscreen synchronization

**Files:**

- Create: `firmware/include/device_controller.h`
- Create: `firmware/src/device_controller.cpp`
- Create: `firmware/test/test_native/test_device_controller.cpp`
- Modify: `firmware/include/transport.h`
- Modify: `firmware/src/transport_ble.cpp`
- Modify: `firmware/src/ui.h`
- Modify: `firmware/src/ui.cpp`
- Modify: `firmware/src/main.cpp`
- Modify: `firmware/platformio.ini`
- Modify: `docs/protocol.md`
- Modify: `docs/hardware.md`

**Interfaces:**

- Produces a complete management-capable firmware for the bridge plan.
- Consumes all previous firmware-plan interfaces.

- [ ] **Step 1: Add failing controller tests with fake persistence and event sinks**

Use injected callables so the native suite proves revision, persistence, and side-effect ordering:

```cpp
void test_controller_confirms_patch_only_after_persistence() {
  RecordingSettingsStore store;
  store.loaded = make_settings(8);
  RecordingEventSink events;
  DeviceController controller(store, events);
  TEST_ASSERT_EQUAL_UINT8(static_cast<uint8_t>(SettingsLoadResult::Loaded),
                          static_cast<uint8_t>(controller.begin()));
  ManagementRequest request = make_always_on_patch(17, 8, true);

  controller.handle(request, 1000);

  TEST_ASSERT_EQUAL_UINT32(9, store.saved.revision);
  TEST_ASSERT_TRUE(store.saved.always_on);
  TEST_ASSERT_EQUAL_STRING("settings.result", events.last_type());
  TEST_ASSERT_EQUAL_UINT32(9, events.last_settings_revision());
}

void test_controller_rejects_stale_revision_without_saving() {
  RecordingSettingsStore store;
  store.loaded = make_settings(9);
  RecordingEventSink events;
  DeviceController controller(store, events);
  TEST_ASSERT_EQUAL_UINT8(static_cast<uint8_t>(SettingsLoadResult::Loaded),
                          static_cast<uint8_t>(controller.begin()));

  controller.handle(make_always_on_patch(18, 8, true), 1000);

  TEST_ASSERT_EQUAL_UINT32(0, store.save_count);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<uint8_t>(ManagementStatus::RevisionConflict),
      static_cast<uint8_t>(events.last_status()));
}
```

Also test touchscreen changes use the same increment/save/event path, identify does not persist,
restart occurs only after a result is queued, forget clears bonds only after its result is queued,
and unchanged settings do not write NVS.

- [ ] **Step 2: Run the native suite and verify failure**

```bash
.venv/bin/pio test -d firmware -e native
```

- [ ] **Step 3: Implement `DeviceController`**

Define small injectable boundaries and use these entry points:

```cpp
class SettingsRepository {
 public:
  virtual ~SettingsRepository() = default;
  virtual SettingsLoadResult load(DeviceSettings& output) = 0;
  virtual bool save(const DeviceSettings& settings) = 0;
};

class ManagementEventSink {
 public:
  virtual ~ManagementEventSink() = default;
  virtual bool publish(uint8_t message_type, uint16_t message_id,
                       const uint8_t* payload, size_t length) = 0;
};

class DeviceController {
 public:
  DeviceController(SettingsRepository& settings, ManagementEventSink& events);
  SettingsLoadResult begin();
  void set_snapshot(const DashboardSnapshot* snapshot);
  void handle(const ManagementRequest& request, uint32_t now_ms);
  void settings_changed_from_ui(const DeviceSettings& candidate, uint32_t now_ms);
  void tick(uint32_t now_ms);
  const DeviceSettings& settings() const;
};
```

Add `NvsSettingsRepository` as the production adapter over `load_device_settings` and
`save_device_settings`; tests use the recording implementation.

`tick` publishes telemetry at most every 30 seconds and immediately after a power-source change.
It also performs deferred restart/forget actions after the corresponding result was queued.

- [ ] **Step 4: Add the two encrypted management characteristics**

Use full UUIDs:

```text
a77e0004-8f7b-4f63-9a53-65f93f0d6d01  encrypted write with response
a77e0005-8f7b-4f63-9a53-65f93f0d6d01  encrypted read and notify
```

The write callback copies at most 512 bytes into a dedicated FreeRTOS queue and returns. Parse and
dispatch only from `transport_loop`. Fragment outbound result/event JSON using the peer MTU from
`NimBLEServer::getPeerMTU(connection_handle)`, capped at 512 bytes and never below the 20-byte
default. Serialize notifications through one queue so result fragments never interleave.

Extend `transport_begin` to accept snapshot and management callbacks and add:

```cpp
bool transport_publish_management(uint8_t message_type, uint16_t message_id,
                                  const uint8_t* payload, size_t length);
```

- [ ] **Step 5: Make UI settings changes bidirectional**

Remove direct NVS writes from `ui.cpp`. Initialize UI with the controller's confirmed settings,
call a `SettingsChangedCallback` after a valid touchscreen edit, and add
`ui_apply_settings(const DeviceSettings&)` for confirmed host changes. Re-render only when the
active screen depends on changed values. Use managed brightness, dim, screen-off, thresholds, and
sound instead of snapshot display defaults after the management capability is active.

- [ ] **Step 6: Wire main and document the contract**

`main.cpp` loads the controller before UI, passes each accepted snapshot to both controller and
UI, polls controller after transport, and continues USB snapshot recovery. Update `docs/protocol.md`
with UUIDs, frame types, envelope fields, command table, errors, capabilities, and compatibility.
Update `docs/hardware.md` with USB-only and optional-battery telemetry expectations.

- [ ] **Step 7: Run all firmware and host regression gates**

```bash
.venv/bin/pio test -d firmware -e native
.venv/bin/pio run -d firmware
.venv/bin/pytest
```

Expected: all pass; no existing snapshot or host tests regress.

- [ ] **Step 8: Flash and perform the firmware acceptance check**

```bash
.venv/bin/pio run -d firmware -t upload
.venv/bin/pio device monitor -d firmware -b 115200
```

Confirm: the dashboard still updates, the settings screen persists after restart, the serial log
reports USB with no battery when appropriate, the `0004`/`0005` characteristics require the bonded
connection, and a five-second physical-button hold still clears bonds.

- [ ] **Step 9: Commit the integrated firmware**

```bash
git add firmware/include/device_controller.h firmware/src/device_controller.cpp \
  firmware/test/test_native/test_device_controller.cpp firmware/include/transport.h \
  firmware/src/transport_ble.cpp firmware/src/ui.h firmware/src/ui.cpp firmware/src/main.cpp \
  firmware/platformio.ini docs/protocol.md docs/hardware.md
git commit -m "feat(firmware): add encrypted device management"
```

## Plan completion gate

Do not begin bridge management work until:

- native tests cover every command, error, migration, revision conflict, and nullable telemetry;
- the ESP32 build passes;
- existing snapshot delivery passes unchanged;
- the physical board exposes encrypted `0004`/`0005` characteristics;
- USB-only hardware reports no battery and no fabricated current draw;
- host and touchscreen setting edits share one persisted revision path.
