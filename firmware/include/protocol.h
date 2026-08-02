#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "dashboard_model.h"

namespace agentmeter {

enum class FrameStatus : uint8_t {
  Ok = 0,
  MalformedFrame = 1,
  TooLarge = 2,
  InvalidJson = 3,
  UnsupportedSchema = 4,
  InvalidModel = 5,
  Incomplete = 0xFF,
};

std::array<uint8_t, 5> make_ack(uint16_t message_id, FrameStatus status);

class Reassembler {
 public:
  FrameStatus push(const uint8_t* frame, size_t length, uint32_t now_ms,
                   DashboardSnapshot& output);
  void reset();

 private:
  std::array<uint8_t, kMaximumSnapshotBytes> buffer_{};
  uint16_t message_id_ = 0;
  uint16_t total_length_ = 0;
  uint16_t received_length_ = 0;
  uint32_t updated_at_ms_ = 0;
  bool active_ = false;
};

}  // namespace agentmeter
