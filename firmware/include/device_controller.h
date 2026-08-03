#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "management_protocol.h"
#include "protocol.h"
#include "settings_store.h"

namespace agentmeter {

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

class DevicePlatform {
 public:
  virtual ~DevicePlatform() = default;
  virtual DeviceInformation information() = 0;
  virtual DeviceTelemetry telemetry(const DeviceSettings& settings) = 0;
  virtual void apply_settings(const DeviceSettings& settings) = 0;
  virtual void identify() = 0;
  virtual void restart() = 0;
  virtual void forget_bonds() = 0;
};

class DeviceController {
 public:
  DeviceController(SettingsRepository& settings, ManagementEventSink& events);
  DeviceController(SettingsRepository& settings, ManagementEventSink& events,
                   DevicePlatform& platform);

  SettingsLoadResult begin();
  void set_snapshot(const DashboardSnapshot* snapshot);
  void handle(const ManagementRequest& request, uint32_t now_ms);
  void settings_changed_from_ui(const DeviceSettings& candidate,
                                uint32_t now_ms);
  void tick(uint32_t now_ms);
  const DeviceSettings& settings() const;
  const DeviceState& state() const;

 private:
  bool publish_result(const ManagementRequest& request,
                      ManagementStatus status);
  bool publish_state_event();
  void refresh_state();
  bool persist_and_apply(DeviceSettings candidate);

  SettingsRepository& settings_repository_;
  ManagementEventSink& event_sink_;
  DevicePlatform& platform_;
  DeviceState state_{};
  const DashboardSnapshot* snapshot_ = nullptr;
  std::array<uint8_t, kMaximumManagementBytes> event_buffer_{};
  uint32_t last_telemetry_poll_ms_ = 0;
  uint32_t last_telemetry_publish_ms_ = 0;
  uint16_t next_event_message_id_ = 1;
  uint32_t restart_ready_at_ms_ = 0;
  uint32_t forget_ready_at_ms_ = 0;
  bool restart_pending_ = false;
  bool forget_pending_ = false;
};

}  // namespace agentmeter
