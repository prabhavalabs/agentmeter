#include "transport.h"

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

#include <array>
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <string>

#include "protocol.h"

namespace agentmeter {
namespace {

constexpr char kServiceUuid[] = "a77e0001-8f7b-4f63-9a53-65f93f0d6d01";
constexpr char kDataUuid[] = "a77e0002-8f7b-4f63-9a53-65f93f0d6d01";
constexpr char kStatusUuid[] = "a77e0003-8f7b-4f63-9a53-65f93f0d6d01";
constexpr char kManagementRequestUuid[] =
    "a77e0004-8f7b-4f63-9a53-65f93f0d6d01";
constexpr char kManagementEventUuid[] =
    "a77e0005-8f7b-4f63-9a53-65f93f0d6d01";
constexpr size_t kMaximumFrameBytes = 512;

struct QueuedFrame {
  uint16_t length = 0;
  std::array<uint8_t, kMaximumFrameBytes> bytes{};
};

QueueHandle_t snapshot_frame_queue = nullptr;
QueueHandle_t management_frame_queue = nullptr;
NimBLECharacteristic* status_characteristic = nullptr;
NimBLECharacteristic* management_event_characteristic = nullptr;
ModelCallback model_callback = nullptr;
ManagementCallback management_callback = nullptr;
Reassembler reassembler;
FragmentReassembler management_reassembler(kManagementRequestMessageType,
                                           kMaximumManagementBytes);
volatile bool connected = false;
volatile bool encrypted = false;
volatile bool reset_reassembler = false;
uint16_t connection_handle = BLE_HS_CONN_HANDLE_NONE;
char device_name[24] = "AgentMeter";

uint16_t frame_message_id(const QueuedFrame& frame) {
  if (frame.length < 4) {
    return 0;
  }
  return static_cast<uint16_t>(frame.bytes[2]) |
         static_cast<uint16_t>(frame.bytes[3] << 8U);
}

class ServerCallbacks final : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
    connected = true;
    encrypted = false;
    connection_handle = info.getConnHandle();
    server->updateConnParams(info.getConnHandle(), 12, 24, 0, 180);
    Serial.printf("BLE: connected to %s\n",
                  info.getAddress().toString().c_str());
  }

  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) override {
    connected = false;
    encrypted = false;
    connection_handle = BLE_HS_CONN_HANDLE_NONE;
    reset_reassembler = true;
    NimBLEDevice::startAdvertising();
    Serial.printf("BLE: disconnected (%d), advertising restarted\n", reason);
  }

  void onAuthenticationComplete(NimBLEConnInfo& info) override {
    if (!info.isEncrypted()) {
      NimBLEDevice::getServer()->disconnect(info.getConnHandle());
      Serial.println("BLE: pairing did not create an encrypted connection");
      return;
    }
    encrypted = true;
    connection_handle = info.getConnHandle();
    Serial.println("BLE: encrypted bond ready");
  }
};

class DataCallbacks final : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic,
               NimBLEConnInfo& info) override {
    if (!info.isEncrypted() || snapshot_frame_queue == nullptr) {
      return;
    }
    const NimBLEAttValue& value = characteristic->getValue();
    if (value.size() == 0 || value.size() > kMaximumFrameBytes) {
      return;
    }
    QueuedFrame frame{};
    frame.length = value.size();
    std::copy(value.data(), value.data() + value.size(), frame.bytes.begin());
    xQueueSend(snapshot_frame_queue, &frame, 0);
  }
};

class ManagementCallbacks final : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic,
               NimBLEConnInfo& info) override {
    if (!info.isEncrypted() || management_frame_queue == nullptr) {
      return;
    }
    const NimBLEAttValue& value = characteristic->getValue();
    if (value.size() == 0 || value.size() > kMaximumFrameBytes) {
      return;
    }
    QueuedFrame frame{};
    frame.length = value.size();
    std::copy(value.data(), value.data() + value.size(), frame.bytes.begin());
    xQueueSend(management_frame_queue, &frame, 0);
  }
};

ServerCallbacks server_callbacks;
DataCallbacks data_callbacks;
ManagementCallbacks management_callbacks;

void process_queued_frames() {
  if (snapshot_frame_queue == nullptr) {
    return;
  }
  if (reset_reassembler) {
    reset_reassembler = false;
    reassembler.reset();
    management_reassembler.reset();
    xQueueReset(snapshot_frame_queue);
    if (management_frame_queue != nullptr) {
      xQueueReset(management_frame_queue);
    }
  }
  QueuedFrame frame{};
  while (xQueueReceive(snapshot_frame_queue, &frame, 0) == pdTRUE) {
    const uint16_t message_id = frame_message_id(frame);
    DashboardSnapshot snapshot{};
    const FrameStatus status =
        reassembler.push(frame.bytes.data(), frame.length, millis(), snapshot);
    if (status == FrameStatus::Incomplete) {
      continue;
    }
    if (status == FrameStatus::Ok && model_callback != nullptr) {
      model_callback(snapshot, millis());
    }
    if (status_characteristic != nullptr) {
      const auto ack = make_ack(message_id, status);
      status_characteristic->setValue(ack.data(), ack.size());
      status_characteristic->notify();
    }
  }
}

ManagementStatus management_status(FrameStatus status) {
  switch (status) {
    case FrameStatus::MalformedFrame:
      return ManagementStatus::MalformedFrame;
    case FrameStatus::TooLarge:
      return ManagementStatus::TooLarge;
    case FrameStatus::InvalidJson:
      return ManagementStatus::InvalidJson;
    case FrameStatus::UnsupportedSchema:
      return ManagementStatus::UnsupportedSchema;
    case FrameStatus::InvalidModel:
      return ManagementStatus::InvalidRequest;
    case FrameStatus::Ok:
    case FrameStatus::Incomplete:
      return ManagementStatus::InvalidRequest;
  }
  return ManagementStatus::InvalidRequest;
}

void publish_management_error(uint16_t message_id, ManagementStatus status) {
  ManagementResult result{};
  result.request_id = message_id;
  result.status = status;
  std::array<uint8_t, kMaximumManagementBytes> payload{};
  const size_t length =
      encode_management_result(result, payload.data(), payload.size());
  if (length > 0) {
    transport_publish_management(kManagementResultMessageType, message_id,
                                 payload.data(), length);
  }
}

void process_management_frames() {
  if (management_frame_queue == nullptr) {
    return;
  }
  QueuedFrame frame{};
  while (xQueueReceive(management_frame_queue, &frame, 0) == pdTRUE) {
    const uint16_t message_id = frame_message_id(frame);
    ReassembledFrame complete{};
    const FrameStatus frame_status = management_reassembler.push(
        frame.bytes.data(), frame.length, millis(), complete);
    if (frame_status == FrameStatus::Incomplete) {
      continue;
    }
    if (frame_status != FrameStatus::Ok) {
      publish_management_error(message_id, management_status(frame_status));
      continue;
    }
    ManagementRequest request{};
    const ManagementStatus parse_status = parse_management_request(
        complete.payload, complete.length, request);
    if (parse_status != ManagementStatus::Ok) {
      publish_management_error(complete.message_id, parse_status);
      continue;
    }
    if (static_cast<uint16_t>(request.request_id) != complete.message_id) {
      publish_management_error(complete.message_id,
                               ManagementStatus::InvalidRequest);
      continue;
    }
    if (management_callback == nullptr) {
      publish_management_error(complete.message_id,
                               ManagementStatus::UnsupportedCommand);
      continue;
    }
    management_callback(request, millis());
  }
}

void build_device_name() {
  const std::string address = NimBLEDevice::getAddress().toString();
  char suffix[5] = "0000";
  if (address.size() >= 5) {
    suffix[0] = static_cast<char>(std::toupper(address[address.size() - 5]));
    suffix[1] = static_cast<char>(std::toupper(address[address.size() - 4]));
    suffix[2] = static_cast<char>(std::toupper(address[address.size() - 2]));
    suffix[3] = static_cast<char>(std::toupper(address[address.size() - 1]));
  }
  std::snprintf(device_name, sizeof(device_name), "AgentMeter-%s", suffix);
}

}  // namespace

bool transport_begin(ModelCallback model_handler,
                     ManagementCallback management_handler) {
  model_callback = model_handler;
  management_callback = management_handler;
  snapshot_frame_queue = xQueueCreate(4, sizeof(QueuedFrame));
  management_frame_queue = xQueueCreate(4, sizeof(QueuedFrame));
  if (snapshot_frame_queue == nullptr || management_frame_queue == nullptr) {
    Serial.println("BLE: unable to allocate transport queues");
    return false;
  }

  NimBLEDevice::init("AgentMeter");
  NimBLEDevice::setMTU(517);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);
  NimBLEDevice::setSecurityAuth(true, false, true);
  build_device_name();
  NimBLEDevice::setDeviceName(device_name);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(&server_callbacks);
  NimBLEService* service = server->createService(kServiceUuid);
  NimBLECharacteristic* data_characteristic = service->createCharacteristic(
      kDataUuid,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR |
          NIMBLE_PROPERTY::WRITE_ENC,
      kMaximumFrameBytes);
  data_characteristic->setCallbacks(&data_callbacks);
  status_characteristic = service->createCharacteristic(
      kStatusUuid,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY |
      NIMBLE_PROPERTY::READ_ENC,
      5);
  NimBLECharacteristic* management_request_characteristic =
      service->createCharacteristic(
          kManagementRequestUuid,
          NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC,
          kMaximumFrameBytes);
  management_request_characteristic->setCallbacks(&management_callbacks);
  management_event_characteristic = service->createCharacteristic(
      kManagementEventUuid,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY |
          NIMBLE_PROPERTY::READ_ENC,
      kMaximumFrameBytes);

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->setName(device_name);
  advertising->addServiceUUID(kServiceUuid);
  advertising->enableScanResponse(true);
  if (!advertising->start()) {
    Serial.println("BLE: advertising failed to start");
    return false;
  }
  Serial.printf("BLE: advertising as %s\n", device_name);
  return true;
}

void transport_loop() {
  process_queued_frames();
  process_management_frames();
  serial_transport_poll(model_callback);
}

bool transport_publish_management(uint8_t message_type, uint16_t message_id,
                                  const uint8_t* payload, size_t length) {
  if (!connected || !encrypted || management_event_characteristic == nullptr ||
      connection_handle == BLE_HS_CONN_HANDLE_NONE || payload == nullptr ||
      length == 0 || length > kMaximumManagementBytes ||
      (message_type != kManagementResultMessageType &&
       message_type != kDeviceEventMessageType)) {
    return false;
  }

  NimBLEServer* server = NimBLEDevice::getServer();
  const uint16_t peer_mtu =
      server == nullptr ? 23 : server->getPeerMTU(connection_handle);
  const size_t maximum_frame_bytes = std::min<size_t>(
      kMaximumFrameBytes,
      std::max<size_t>(20, peer_mtu > 3 ? peer_mtu - 3 : 20));
  const size_t maximum_fragment_bytes =
      maximum_frame_bytes - kFrameHeaderBytes;
  std::array<uint8_t, kMaximumFrameBytes> frame{};
  const uint16_t total_length = static_cast<uint16_t>(length);
  size_t offset = 0;
  while (offset < length) {
    const size_t fragment_length =
        std::min(maximum_fragment_bytes, length - offset);
    frame[0] = kProtocolVersion;
    frame[1] = message_type;
    frame[2] = static_cast<uint8_t>(message_id);
    frame[3] = static_cast<uint8_t>(message_id >> 8U);
    frame[4] = static_cast<uint8_t>(total_length);
    frame[5] = static_cast<uint8_t>(total_length >> 8U);
    frame[6] = static_cast<uint8_t>(offset);
    frame[7] = static_cast<uint8_t>(offset >> 8U);
    std::memcpy(frame.data() + kFrameHeaderBytes, payload + offset,
                fragment_length);
    const size_t frame_length = kFrameHeaderBytes + fragment_length;
    management_event_characteristic->setValue(frame.data(), frame_length);
    if (!management_event_characteristic->notify(
            frame.data(), frame_length, connection_handle)) {
      return false;
    }
    offset += fragment_length;
    if (offset < length) {
      delay(1);
    }
  }
  return true;
}

bool transport_is_connected() {
  return connected || serial_transport_has_received();
}

const char* transport_device_name() { return device_name; }

void transport_clear_bonds() {
  NimBLEServer* server = NimBLEDevice::getServer();
  if (server != nullptr) {
    for (const uint16_t connection_handle : server->getPeerDevices()) {
      server->disconnect(connection_handle);
    }
  }
  NimBLEDevice::deleteAllBonds();
  connected = false;
  encrypted = false;
  connection_handle = BLE_HS_CONN_HANDLE_NONE;
  reassembler.reset();
  management_reassembler.reset();
  if (snapshot_frame_queue != nullptr) {
    xQueueReset(snapshot_frame_queue);
  }
  if (management_frame_queue != nullptr) {
    xQueueReset(management_frame_queue);
  }
  NimBLEDevice::startAdvertising();
  Serial.println("BLE: all saved bonds cleared");
}

}  // namespace agentmeter
