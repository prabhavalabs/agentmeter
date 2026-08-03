#include "device_controller.h"

#include <limits>

namespace agentmeter {
namespace {

constexpr uint32_t kTelemetryPollIntervalMs = 1000;
constexpr uint32_t kTelemetryPublishIntervalMs = 30000;
constexpr uint32_t kDeferredActionDelayMs = 250;

class NullDevicePlatform final : public DevicePlatform {
 public:
  DeviceInformation information() override { return {}; }
  DeviceTelemetry telemetry(const DeviceSettings& settings) override {
    DeviceTelemetry value{};
    value.brightness_percent = settings.brightness_percent;
    return value;
  }
  void apply_settings(const DeviceSettings&) override {}
  void identify() override {}
  void restart() override {}
  void forget_bonds() override {}
};

DevicePlatform& null_device_platform() {
  static NullDevicePlatform platform;
  return platform;
}

uint32_t next_revision(uint32_t revision) {
  return revision == std::numeric_limits<uint32_t>::max() ? 1 : revision + 1;
}

bool power_state_changed(const DeviceTelemetry& previous,
                         const DeviceTelemetry& current) {
  return previous.power_source != current.power_source ||
         previous.usb_present != current.usb_present ||
         previous.battery_present != current.battery_present ||
         previous.has_charging != current.has_charging ||
         (current.has_charging && previous.charging != current.charging);
}

}  // namespace

DeviceController::DeviceController(SettingsRepository& settings,
                                   ManagementEventSink& events)
    : DeviceController(settings, events, null_device_platform()) {}

DeviceController::DeviceController(SettingsRepository& settings,
                                   ManagementEventSink& events,
                                   DevicePlatform& platform)
    : settings_repository_(settings),
      event_sink_(events),
      platform_(platform) {}

SettingsLoadResult DeviceController::begin() {
  DeviceSettings loaded{};
  const SettingsLoadResult result = settings_repository_.load(loaded);
  if (result != SettingsLoadResult::StorageError &&
      validate_device_settings(loaded, nullptr)) {
    state_.settings = loaded;
  } else {
    state_.settings = DeviceSettings{};
  }
  state_.information = platform_.information();
  state_.telemetry = platform_.telemetry(state_.settings);
  platform_.apply_settings(state_.settings);
  return result;
}

void DeviceController::set_snapshot(const DashboardSnapshot* snapshot) {
  snapshot_ = snapshot;
}

void DeviceController::refresh_state() {
  state_.information = platform_.information();
  state_.telemetry = platform_.telemetry(state_.settings);
}

bool DeviceController::publish_result(const ManagementRequest& request,
                                      ManagementStatus status) {
  refresh_state();
  ManagementResult result{};
  result.request_id = request.request_id;
  result.command = request.command;
  result.status = status;
  result.has_device_state =
      request.command == ManagementCommand::DeviceGet ||
      request.command == ManagementCommand::TelemetryGet ||
      request.command == ManagementCommand::SettingsGet ||
      request.command == ManagementCommand::SettingsPatch;
  result.device_state = state_;
  const size_t length = encode_management_result(
      result, event_buffer_.data(), event_buffer_.size());
  return length > 0 && event_sink_.publish(
                           kManagementResultMessageType,
                           static_cast<uint16_t>(request.request_id),
                           event_buffer_.data(), length);
}

bool DeviceController::publish_state_event() {
  refresh_state();
  const size_t length = encode_device_state_event(
      state_, event_buffer_.data(), event_buffer_.size());
  if (length == 0) {
    return false;
  }
  const uint16_t message_id = next_event_message_id_++;
  if (next_event_message_id_ == 0) {
    next_event_message_id_ = 1;
  }
  return event_sink_.publish(kDeviceEventMessageType, message_id,
                             event_buffer_.data(), length);
}

bool DeviceController::persist_and_apply(DeviceSettings candidate) {
  candidate.revision = next_revision(state_.settings.revision);
  if (!settings_repository_.save(candidate)) {
    return false;
  }
  state_.settings = candidate;
  platform_.apply_settings(state_.settings);
  return true;
}

void DeviceController::handle(const ManagementRequest& request,
                              uint32_t now_ms) {
  switch (request.command) {
    case ManagementCommand::DeviceGet:
    case ManagementCommand::TelemetryGet:
    case ManagementCommand::SettingsGet:
      publish_result(request, ManagementStatus::Ok);
      return;

    case ManagementCommand::SettingsPatch: {
      if (request.settings_patch.base_revision != state_.settings.revision) {
        publish_result(request, ManagementStatus::RevisionConflict);
        return;
      }
      DeviceSettings candidate = state_.settings;
      const ManagementStatus patch_status = apply_settings_patch(
          request.settings_patch, snapshot_, candidate);
      if (patch_status != ManagementStatus::Ok) {
        publish_result(request, patch_status);
        return;
      }
      if (device_settings_equal(candidate, state_.settings)) {
        publish_result(request, ManagementStatus::Ok);
        return;
      }
      if (!persist_and_apply(candidate)) {
        publish_result(request, ManagementStatus::PersistenceFailed);
        return;
      }
      last_telemetry_poll_ms_ = now_ms;
      publish_result(request, ManagementStatus::Ok);
      return;
    }

    case ManagementCommand::DeviceIdentify:
      if (publish_result(request, ManagementStatus::Ok)) {
        platform_.identify();
      }
      return;

    case ManagementCommand::DeviceRestart:
      restart_pending_ = publish_result(request, ManagementStatus::Ok);
      restart_ready_at_ms_ = now_ms + kDeferredActionDelayMs;
      return;

    case ManagementCommand::DeviceForget:
      forget_pending_ = publish_result(request, ManagementStatus::Ok);
      forget_ready_at_ms_ = now_ms + kDeferredActionDelayMs;
      return;
  }
}

void DeviceController::settings_changed_from_ui(const DeviceSettings& input,
                                                uint32_t now_ms) {
  DeviceSettings candidate = input;
  candidate.revision = state_.settings.revision;
  if (!validate_device_settings(candidate, snapshot_) ||
      device_settings_equal(candidate, state_.settings) ||
      !persist_and_apply(candidate)) {
    return;
  }
  last_telemetry_poll_ms_ = now_ms;
  publish_state_event();
}

void DeviceController::tick(uint32_t now_ms) {
  if (restart_pending_ &&
      static_cast<int32_t>(now_ms - restart_ready_at_ms_) >= 0) {
    restart_pending_ = false;
    platform_.restart();
  }
  if (forget_pending_ &&
      static_cast<int32_t>(now_ms - forget_ready_at_ms_) >= 0) {
    forget_pending_ = false;
    platform_.forget_bonds();
  }

  if (now_ms - last_telemetry_poll_ms_ < kTelemetryPollIntervalMs) {
    return;
  }
  last_telemetry_poll_ms_ = now_ms;
  const DeviceTelemetry previous = state_.telemetry;
  state_.telemetry = platform_.telemetry(state_.settings);
  if (power_state_changed(previous, state_.telemetry) ||
      now_ms - last_telemetry_publish_ms_ >= kTelemetryPublishIntervalMs) {
    last_telemetry_publish_ms_ = now_ms;
    publish_state_event();
  }
}

const DeviceSettings& DeviceController::settings() const {
  return state_.settings;
}

const DeviceState& DeviceController::state() const { return state_; }

}  // namespace agentmeter
