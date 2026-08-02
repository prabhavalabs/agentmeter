#include "protocol.h"

#include <cstring>

namespace agentmeter {
namespace {

constexpr size_t kHeaderBytes = 8;
constexpr uint8_t kFrameVersion = 1;
constexpr uint8_t kSnapshotMessageType = 1;
constexpr uint32_t kReassemblyTimeoutMs = 2000;

uint16_t little_endian_u16(const uint8_t* bytes) {
  return static_cast<uint16_t>(bytes[0]) |
         static_cast<uint16_t>(bytes[1] << 8U);
}

FrameStatus frame_status(ParseStatus status) {
  return static_cast<FrameStatus>(static_cast<uint8_t>(status));
}

}  // namespace

std::array<uint8_t, 5> make_ack(uint16_t message_id, FrameStatus status) {
  return {
      kFrameVersion,
      0x81,
      static_cast<uint8_t>(message_id & 0xFF),
      static_cast<uint8_t>(message_id >> 8U),
      static_cast<uint8_t>(status),
  };
}

FrameStatus Reassembler::push(const uint8_t* frame, size_t length,
                              uint32_t now_ms, DashboardSnapshot& output) {
  if (active_ && now_ms - updated_at_ms_ > kReassemblyTimeoutMs) {
    reset();
  }
  if (frame == nullptr || length <= kHeaderBytes || frame[0] != kFrameVersion ||
      frame[1] != kSnapshotMessageType) {
    reset();
    return FrameStatus::MalformedFrame;
  }

  const uint16_t message_id = little_endian_u16(frame + 2);
  const uint16_t total_length = little_endian_u16(frame + 4);
  const uint16_t offset = little_endian_u16(frame + 6);
  const size_t fragment_length = length - kHeaderBytes;
  if (total_length == 0 || total_length > buffer_.size() ||
      static_cast<size_t>(offset) + fragment_length > total_length) {
    reset();
    return total_length > buffer_.size() ? FrameStatus::TooLarge
                                         : FrameStatus::MalformedFrame;
  }

  if (!active_ || message_id != message_id_) {
    if (offset != 0) {
      reset();
      return FrameStatus::MalformedFrame;
    }
    reset();
    active_ = true;
    message_id_ = message_id;
    total_length_ = total_length;
  }
  if (total_length != total_length_ || offset != received_length_) {
    reset();
    return FrameStatus::MalformedFrame;
  }

  std::memcpy(buffer_.data() + offset, frame + kHeaderBytes, fragment_length);
  received_length_ = static_cast<uint16_t>(received_length_ + fragment_length);
  updated_at_ms_ = now_ms;
  if (received_length_ != total_length_) {
    return FrameStatus::Incomplete;
  }

  DashboardSnapshot candidate{};
  const ParseStatus parse_status =
      parse_snapshot(buffer_.data(), total_length_, candidate);
  reset();
  if (parse_status != ParseStatus::Ok) {
    return frame_status(parse_status);
  }
  if (candidate.message_id != message_id) {
    return FrameStatus::InvalidModel;
  }
  output = candidate;
  return FrameStatus::Ok;
}

void Reassembler::reset() {
  message_id_ = 0;
  total_length_ = 0;
  received_length_ = 0;
  updated_at_ms_ = 0;
  active_ = false;
}

}  // namespace agentmeter
