#include "transport.h"

#include <Arduino.h>

#include <array>

namespace agentmeter {
namespace {

std::array<uint8_t, kMaximumSnapshotBytes> serial_buffer{};
size_t serial_length = 0;
bool serial_overflow = false;
bool serial_received = false;

void finish_serial_line(ModelCallback callback) {
  if (serial_overflow) {
    Serial.println("ACK 0 2");
  } else if (serial_length > 0) {
    DashboardSnapshot snapshot{};
    const ParseStatus status =
        parse_snapshot(serial_buffer.data(), serial_length, snapshot);
    const uint16_t message_id =
        status == ParseStatus::Ok ? snapshot.message_id : 0;
    if (status == ParseStatus::Ok && callback != nullptr) {
      serial_received = true;
      callback(snapshot, millis());
    }
    Serial.printf("ACK %u %u\n", message_id, static_cast<uint8_t>(status));
  }
  serial_length = 0;
  serial_overflow = false;
}

}  // namespace

void serial_transport_poll(ModelCallback callback) {
  while (Serial.available() > 0) {
    const int value = Serial.read();
    if (value < 0) {
      return;
    }
    if (value == '\n') {
      finish_serial_line(callback);
    } else if (!serial_overflow) {
      if (serial_length < serial_buffer.size()) {
        serial_buffer[serial_length++] = static_cast<uint8_t>(value);
      } else {
        serial_overflow = true;
      }
    }
  }
}

bool serial_transport_has_received() { return serial_received; }

}  // namespace agentmeter
