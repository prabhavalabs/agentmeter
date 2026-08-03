#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "dashboard_model.h"

namespace agentmeter {

inline constexpr size_t kFrameHeaderBytes = 8;
inline constexpr uint8_t kProtocolVersion = 1;
inline constexpr uint8_t kSnapshotMessageType = 0x01;
inline constexpr uint8_t kManagementRequestMessageType = 0x02;
inline constexpr uint8_t kSnapshotAckMessageType = 0x81;
inline constexpr uint8_t kManagementResultMessageType = 0x82;
inline constexpr uint8_t kDeviceEventMessageType = 0x83;

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

struct ReassembledFrame {
  // Valid until the owning reassembler receives another fragment.
  const uint8_t* payload = nullptr;
  uint16_t message_id = 0;
  uint16_t length = 0;
  uint8_t message_type = 0;
};

class FragmentReassembler {
 public:
  FragmentReassembler(uint8_t expected_message_type,
                      size_t maximum_payload_bytes);
  FrameStatus push(const uint8_t* frame, size_t length, uint32_t now_ms,
                   ReassembledFrame& output);
  void reset();

 private:
  std::array<uint8_t, kMaximumSnapshotBytes> buffer_{};
  size_t maximum_payload_bytes_ = kMaximumSnapshotBytes;
  uint16_t message_id_ = 0;
  uint16_t total_length_ = 0;
  uint16_t received_length_ = 0;
  uint32_t updated_at_ms_ = 0;
  uint8_t expected_message_type_ = 0;
  bool active_ = false;
};

class Reassembler {
 public:
  Reassembler();
  FrameStatus push(const uint8_t* frame, size_t length, uint32_t now_ms,
                   DashboardSnapshot& output);
  void reset();

 private:
  FragmentReassembler reassembler_;
};

}  // namespace agentmeter
