#include "transport.h"

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

#include <array>
#include <cctype>
#include <cstdio>
#include <string>

#include "protocol.h"

namespace agentmeter {
namespace {

constexpr char kServiceUuid[] = "a77e0001-8f7b-4f63-9a53-65f93f0d6d01";
constexpr char kDataUuid[] = "a77e0002-8f7b-4f63-9a53-65f93f0d6d01";
constexpr char kStatusUuid[] = "a77e0003-8f7b-4f63-9a53-65f93f0d6d01";
constexpr size_t kMaximumFrameBytes = 512;

struct QueuedFrame {
  uint16_t length = 0;
  std::array<uint8_t, kMaximumFrameBytes> bytes{};
};

QueueHandle_t frame_queue = nullptr;
NimBLECharacteristic* status_characteristic = nullptr;
ModelCallback model_callback = nullptr;
Reassembler reassembler;
volatile bool connected = false;
volatile bool reset_reassembler = false;
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
    server->updateConnParams(info.getConnHandle(), 12, 24, 0, 180);
    Serial.printf("BLE: connected to %s\n",
                  info.getAddress().toString().c_str());
  }

  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) override {
    connected = false;
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
    Serial.println("BLE: encrypted bond ready");
  }
};

class DataCallbacks final : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic,
               NimBLEConnInfo& info) override {
    if (!info.isEncrypted() || frame_queue == nullptr) {
      return;
    }
    const NimBLEAttValue& value = characteristic->getValue();
    if (value.size() == 0 || value.size() > kMaximumFrameBytes) {
      return;
    }
    QueuedFrame frame{};
    frame.length = value.size();
    std::copy(value.data(), value.data() + value.size(), frame.bytes.begin());
    xQueueSend(frame_queue, &frame, 0);
  }
};

ServerCallbacks server_callbacks;
DataCallbacks data_callbacks;

void process_queued_frames() {
  if (frame_queue == nullptr) {
    return;
  }
  if (reset_reassembler) {
    reset_reassembler = false;
    reassembler.reset();
    xQueueReset(frame_queue);
  }
  QueuedFrame frame{};
  while (xQueueReceive(frame_queue, &frame, 0) == pdTRUE) {
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

bool transport_begin(ModelCallback callback) {
  model_callback = callback;
  frame_queue = xQueueCreate(4, sizeof(QueuedFrame));
  if (frame_queue == nullptr) {
    Serial.println("BLE: unable to allocate frame queue");
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
  serial_transport_poll(model_callback);
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
  reassembler.reset();
  if (frame_queue != nullptr) {
    xQueueReset(frame_queue);
  }
  NimBLEDevice::startAdvertising();
  Serial.println("BLE: all saved bonds cleared");
}

}  // namespace agentmeter
