#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace agentmeter {

inline constexpr size_t kMaximumSnapshotBytes = 4096;
inline constexpr size_t kMaximumProviders = 4;
inline constexpr size_t kMaximumWindows = 3;
inline constexpr size_t kDeviceTextBytes = 24;
inline constexpr size_t kEventIdBytes = 97;

enum class ParseStatus : uint8_t {
  Ok = 0,
  TooLarge = 2,
  InvalidJson = 3,
  UnsupportedSchema = 4,
  InvalidModel = 5,
};

enum class ProviderStatus : uint8_t {
  Ok,
  Stale,
  Error,
  Unavailable,
};

enum class EventKind : uint8_t {
  Threshold,
  Reset,
  ProviderError,
};

enum class EventLevel : uint8_t {
  Info,
  Warning,
  Critical,
};

struct QuotaWindow {
  std::array<char, kDeviceTextBytes> kind{};
  std::array<char, kDeviceTextBytes> label{};
  int16_t used_percent = -1;
  bool has_reset = false;
  int64_t reset_at_epoch = 0;
};

struct ProviderSnapshot {
  std::array<char, kDeviceTextBytes> id{};
  std::array<char, kDeviceTextBytes> name{};
  ProviderStatus status = ProviderStatus::Unavailable;
  std::array<QuotaWindow, kMaximumWindows> windows{};
  uint8_t window_count = 0;
};

struct DisplaySettings {
  uint8_t brightness_percent = 55;
  uint32_t dim_after_seconds = 300;
  uint32_t screen_off_after_seconds = 1800;
  std::array<uint8_t, 3> alert_thresholds{75, 90, 0};
  uint8_t alert_threshold_count = 2;
  bool sound_enabled = false;
};

struct DisplayEvent {
  bool present = false;
  std::array<char, kEventIdBytes> id{};
  EventKind kind = EventKind::Threshold;
  EventLevel level = EventLevel::Info;
  int64_t expires_at_epoch = 0;
};

struct DashboardSnapshot {
  uint8_t schema_version = 1;
  uint16_t message_id = 0;
  int64_t generated_at_epoch = 0;
  uint32_t stale_after_seconds = 180;
  std::array<ProviderSnapshot, kMaximumProviders> providers{};
  uint8_t provider_count = 0;
  DisplaySettings display{};
  DisplayEvent event{};
};

ParseStatus parse_snapshot(const uint8_t* payload, size_t length,
                           DashboardSnapshot& output);

int64_t estimated_epoch(const DashboardSnapshot& snapshot,
                        uint32_t received_at_ms, uint32_t now_ms);
int64_t seconds_until_reset(int64_t reset_at_epoch, int64_t now_epoch);
bool is_stale(const DashboardSnapshot& snapshot, uint32_t received_at_ms,
              uint32_t now_ms);

}  // namespace agentmeter
