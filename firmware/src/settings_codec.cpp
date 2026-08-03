#include "settings_codec.h"

#include <cstring>

namespace agentmeter {
namespace {

constexpr std::array<uint8_t, 4> kMagic{'A', 'M', 'S', 'T'};
constexpr uint8_t kBlobVersion = 1;
constexpr size_t kMinimumBlobBytes = 28;

uint32_t crc32(const uint8_t* bytes, size_t length) {
  uint32_t crc = 0xFFFFFFFFU;
  for (size_t index = 0; index < length; ++index) {
    crc ^= bytes[index];
    for (uint8_t bit = 0; bit < 8; ++bit) {
      const uint32_t mask = 0U - (crc & 1U);
      crc = (crc >> 1U) ^ (0xEDB88320U & mask);
    }
  }
  return ~crc;
}

class BlobWriter {
 public:
  explicit BlobWriter(SettingsBlob& output) : output_(output) {}

  bool write_u8(uint8_t value) {
    if (position_ >= output_.bytes.size()) {
      return false;
    }
    output_.bytes[position_++] = value;
    return true;
  }

  bool write_u32(uint32_t value) {
    return write_u8(static_cast<uint8_t>(value)) &&
           write_u8(static_cast<uint8_t>(value >> 8U)) &&
           write_u8(static_cast<uint8_t>(value >> 16U)) &&
           write_u8(static_cast<uint8_t>(value >> 24U));
  }

  bool write_bytes(const uint8_t* bytes, size_t length) {
    if (bytes == nullptr || position_ + length > output_.bytes.size()) {
      return false;
    }
    std::memcpy(output_.bytes.data() + position_, bytes, length);
    position_ += length;
    return true;
  }

  bool write_provider_ids(const ProviderIdList& list) {
    if (!write_u8(list.count)) {
      return false;
    }
    for (uint8_t index = 0; index < list.count; ++index) {
      const char* provider_id = list.values[index].data();
      const size_t length = std::strlen(provider_id);
      if (!write_u8(static_cast<uint8_t>(length)) ||
          !write_bytes(reinterpret_cast<const uint8_t*>(provider_id), length)) {
        return false;
      }
    }
    return true;
  }

  size_t position() const { return position_; }

 private:
  SettingsBlob& output_;
  size_t position_ = 0;
};

class BlobReader {
 public:
  BlobReader(const uint8_t* bytes, size_t length)
      : bytes_(bytes), length_(length) {}

  bool read_u8(uint8_t& value) {
    if (position_ >= length_) {
      return false;
    }
    value = bytes_[position_++];
    return true;
  }

  bool read_u32(uint32_t& value) {
    uint8_t first = 0;
    uint8_t second = 0;
    uint8_t third = 0;
    uint8_t fourth = 0;
    if (!read_u8(first) || !read_u8(second) || !read_u8(third) ||
        !read_u8(fourth)) {
      return false;
    }
    value = static_cast<uint32_t>(first) |
            (static_cast<uint32_t>(second) << 8U) |
            (static_cast<uint32_t>(third) << 16U) |
            (static_cast<uint32_t>(fourth) << 24U);
    return true;
  }

  bool read_provider_ids(ProviderIdList& list) {
    uint8_t count = 0;
    if (!read_u8(count) || count > list.values.size()) {
      return false;
    }
    list = {};
    list.count = count;
    for (uint8_t index = 0; index < count; ++index) {
      uint8_t length = 0;
      if (!read_u8(length) || length == 0 || length >= kDeviceTextBytes ||
          position_ + length > length_) {
        return false;
      }
      std::memcpy(list.values[index].data(), bytes_ + position_, length);
      position_ += length;
    }
    return true;
  }

  size_t position() const { return position_; }

 private:
  const uint8_t* bytes_;
  size_t length_;
  size_t position_ = 0;
};

uint32_t read_u32_at(const uint8_t* bytes) {
  return static_cast<uint32_t>(bytes[0]) |
         (static_cast<uint32_t>(bytes[1]) << 8U) |
         (static_cast<uint32_t>(bytes[2]) << 16U) |
         (static_cast<uint32_t>(bytes[3]) << 24U);
}

}  // namespace

bool encode_settings_blob(const DeviceSettings& settings, SettingsBlob& output) {
  output = {};
  if (!validate_device_settings(settings, nullptr)) {
    return false;
  }

  BlobWriter writer(output);
  uint8_t flags = 0;
  flags |= settings.always_on ? 0x01U : 0U;
  flags |= settings.full_view ? 0x02U : 0U;
  flags |= settings.sound_enabled ? 0x04U : 0U;
  if (!writer.write_bytes(kMagic.data(), kMagic.size()) ||
      !writer.write_u8(kBlobVersion) || !writer.write_u32(settings.revision) ||
      !writer.write_u8(flags) ||
      !writer.write_u8(settings.rotation_seconds) ||
      !writer.write_u8(settings.brightness_percent) ||
      !writer.write_u32(settings.dim_after_seconds) ||
      !writer.write_u32(settings.screen_off_after_seconds) ||
      !writer.write_u8(settings.alert_threshold_count)) {
    return false;
  }
  for (uint8_t index = 0; index < settings.alert_threshold_count; ++index) {
    if (!writer.write_u8(settings.alert_thresholds[index])) {
      return false;
    }
  }
  if (!writer.write_provider_ids(settings.hidden_provider_ids) ||
      !writer.write_provider_ids(settings.provider_order)) {
    return false;
  }

  const uint32_t checksum = crc32(output.bytes.data(), writer.position());
  if (!writer.write_u32(checksum)) {
    return false;
  }
  output.length = static_cast<uint16_t>(writer.position());
  return true;
}

SettingsDecodeStatus decode_settings_blob(const uint8_t* bytes, size_t length,
                                          DeviceSettings& output) {
  if (length > kMaximumSettingsBlobBytes) {
    return SettingsDecodeStatus::TooLarge;
  }
  if (bytes == nullptr || length < kMinimumBlobBytes ||
      std::memcmp(bytes, kMagic.data(), kMagic.size()) != 0) {
    return SettingsDecodeStatus::Malformed;
  }
  if (bytes[kMagic.size()] != kBlobVersion) {
    return SettingsDecodeStatus::UnsupportedVersion;
  }

  const size_t content_length = length - sizeof(uint32_t);
  if (crc32(bytes, content_length) != read_u32_at(bytes + content_length)) {
    return SettingsDecodeStatus::InvalidChecksum;
  }

  BlobReader reader(bytes + kMagic.size() + 1,
                    content_length - kMagic.size() - 1);
  DeviceSettings candidate{};
  uint8_t flags = 0;
  if (!reader.read_u32(candidate.revision) || !reader.read_u8(flags) ||
      (flags & 0xF8U) != 0 ||
      !reader.read_u8(candidate.rotation_seconds) ||
      !reader.read_u8(candidate.brightness_percent) ||
      !reader.read_u32(candidate.dim_after_seconds) ||
      !reader.read_u32(candidate.screen_off_after_seconds) ||
      !reader.read_u8(candidate.alert_threshold_count) ||
      candidate.alert_threshold_count == 0 ||
      candidate.alert_threshold_count > candidate.alert_thresholds.size()) {
    return SettingsDecodeStatus::Malformed;
  }
  candidate.always_on = (flags & 0x01U) != 0;
  candidate.full_view = (flags & 0x02U) != 0;
  candidate.sound_enabled = (flags & 0x04U) != 0;
  candidate.alert_thresholds.fill(0);
  for (uint8_t index = 0; index < candidate.alert_threshold_count; ++index) {
    if (!reader.read_u8(candidate.alert_thresholds[index])) {
      return SettingsDecodeStatus::Malformed;
    }
  }
  if (!reader.read_provider_ids(candidate.hidden_provider_ids) ||
      !reader.read_provider_ids(candidate.provider_order) ||
      reader.position() != content_length - kMagic.size() - 1) {
    return SettingsDecodeStatus::Malformed;
  }
  if (!validate_device_settings(candidate, nullptr)) {
    return SettingsDecodeStatus::InvalidModel;
  }
  output = candidate;
  return SettingsDecodeStatus::Ok;
}

bool migrate_legacy_settings(const LegacySettings& legacy,
                             DeviceSettings& output) {
  DeviceSettings candidate{};
  candidate.revision = 1;
  candidate.always_on = legacy.always_on;
  candidate.full_view = legacy.full_view;
  candidate.rotation_seconds = legacy.rotation_seconds;
  candidate.hidden_provider_ids = legacy.hidden_provider_ids;
  if (!validate_device_settings(candidate, nullptr)) {
    return false;
  }
  output = candidate;
  return true;
}

}  // namespace agentmeter
