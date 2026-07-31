#include <Arduino.h>

namespace {
constexpr unsigned long kHeartbeatIntervalMs = 5000;
unsigned long lastHeartbeatMs = 0;
}  // namespace

void setup() {
  Serial.begin(115200);
  delay(250);

  Serial.println();
  Serial.print("AgentMeter firmware ");
  Serial.println(AGENTMETER_VERSION);
  Serial.println("Hardware bring-up scaffold ready.");
}

void loop() {
  const unsigned long now = millis();
  if (now - lastHeartbeatMs >= kHeartbeatIntervalMs) {
    lastHeartbeatMs = now;
    Serial.println("AgentMeter heartbeat");
  }

  delay(10);
}
