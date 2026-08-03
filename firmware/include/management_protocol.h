#pragma once

#include <cstddef>
#include <cstdint>

#include "management_model.h"

namespace agentmeter {

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

ManagementStatus parse_management_request(const uint8_t* payload,
                                          size_t length,
                                          ManagementRequest& output);
size_t encode_management_result(const ManagementResult& result,
                                uint8_t* output, size_t output_size);
size_t encode_device_state_event(const DeviceState& state, uint8_t* output,
                                 size_t output_size);

}  // namespace agentmeter
