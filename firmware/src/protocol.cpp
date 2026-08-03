#include "protocol.h"

#include <cstring>

namespace agentmeter {
namespace {

constexpr uint32_t kReassemblyTimeoutMs = 2000;

uint16_t little_endian_u16(const uint8_t* bytes) {
  return static_cast<uint16_t>(bytes[0]) |
         static_cast<uint16_t>(bytes[1] << 8U);
}

FrameStatus status_from_parse(ParseStatus status) {
  return static_cast<FrameStatus>(static_cast<uint8_t>(status));
}

}  // namespace

std::array<uint8_t, 5> make_ack(uint16_t message_id, FrameStatus status) {
  return {
      kProtocolVersion,
      kSnapshotAckMessageType,
      static_cast<uint8_t>(message_id & 0xFF),
      static_cast<uint8_t>(message_id >> 8U),
      static_cast<uint8_t>(status),
  };
}

FragmentReassembler::FragmentReassembler(uint8_t expected_message_type,
                                         size_t maximum_payload_bytes)
    : maximum_payload_bytes_(maximum_payload_bytes),
      expected_message_type_(expected_message_type) {
  if (maximum_payload_bytes_ > buffer_.size()) {
    maximum_payload_bytes_ = buffer_.size();
  }
}

FrameStatus FragmentReassembler::push(const uint8_t* frame, size_t length,
                                      uint32_t now_ms,
                                      ReassembledFrame& output) {
  if (active_ && now_ms - updated_at_ms_ > kReassemblyTimeoutMs) {
    reset();
  }
  if (frame == nullptr || length <= kFrameHeaderBytes ||
      frame[0] != kProtocolVersion || frame[1] != expected_message_type_) {
    reset();
    return FrameStatus::MalformedFrame;
  }

  const uint16_t message_id = little_endian_u16(frame + 2);
  const uint16_t total_length = little_endian_u16(frame + 4);
  const uint16_t offset = little_endian_u16(frame + 6);
  const size_t fragment_length = length - kFrameHeaderBytes;
  if (total_length == 0 || total_length > maximum_payload_bytes_ ||
      static_cast<size_t>(offset) + fragment_length > total_length) {
    reset();
    return total_length > maximum_payload_bytes_ ? FrameStatus::TooLarge
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

  std::memcpy(buffer_.data() + offset, frame + kFrameHeaderBytes,
              fragment_length);
  received_length_ = static_cast<uint16_t>(received_length_ + fragment_length);
  updated_at_ms_ = now_ms;
  if (received_length_ != total_length_) {
    return FrameStatus::Incomplete;
  }

  output.message_id = message_id_;
  output.length = total_length_;
  output.message_type = expected_message_type_;
  output.payload = buffer_.data();
  reset();
  return FrameStatus::Ok;
}

void FragmentReassembler::reset() {
  message_id_ = 0;
  total_length_ = 0;
  received_length_ = 0;
  updated_at_ms_ = 0;
  active_ = false;
}

Reassembler::Reassembler()
    : reassembler_(kSnapshotMessageType, kMaximumSnapshotBytes) {}

FrameStatus Reassembler::push(const uint8_t* frame, size_t length,
                              uint32_t now_ms, DashboardSnapshot& output) {
  ReassembledFrame complete{};
  const FrameStatus reassembly_status =
      reassembler_.push(frame, length, now_ms, complete);
  if (reassembly_status != FrameStatus::Ok) {
    return reassembly_status;
  }

  DashboardSnapshot candidate{};
  const ParseStatus parse_status =
      parse_snapshot(complete.payload, complete.length, candidate);
  if (parse_status != ParseStatus::Ok) {
    return status_from_parse(parse_status);
  }
  if (candidate.message_id != complete.message_id) {
    return FrameStatus::InvalidModel;
  }
  output = candidate;
  return FrameStatus::Ok;
}

void Reassembler::reset() {
  reassembler_.reset();
}

}  // namespace agentmeter
