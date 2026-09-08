#pragma once
#include <ArduinoJson.h>

// Call before HAL/ADC/BLE initialization. No private material is exposed by API.
void unitSetup();
bool unitClear();
const char* unitId();
uint32_t unitKeygenMs();
const char* unitFailStage();
void unitReply(JsonDocument& reply);
void unitSign(JsonDocument& request, JsonDocument& reply);
