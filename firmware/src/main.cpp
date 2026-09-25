// Board entry point. F1 brings up the screen, canvas, USB link and inputs.
#include <Arduino.h>

#include "board/pins.h"

void setup() {
  pinMode(pins::kBacklight, OUTPUT);
  digitalWrite(pins::kBacklight, HIGH);
  pinMode(pins::kAmpEnable, OUTPUT);
  digitalWrite(pins::kAmpEnable, HIGH);  // amp off by default
  Serial.begin(921600);
}

void loop() {
  static uint32_t last = 0;
  if (millis() - last > 2000) {
    last = millis();
    Serial.printf("{\"t\":\"hello\",\"fw\":\"%s\",\"sha\":\"%s\"}\n", BOOP_FW_VERSION, BOOP_GIT_SHA);
  }
  delay(10);
}
