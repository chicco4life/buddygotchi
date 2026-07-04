#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include <esp_ota_ops.h>
#include <mbedtls/base64.h>
#include <mbedtls/sha256.h>
#include <M5StickCPlus2.h>
#include "ble_bridge.h"

// Companion to xfer.h. Same envelope shape (ack/ok/n/error), same
// per-frame ack discipline — the Mac side gets back-pressure for free.
//
// The flow:
//   ota_begin {size, sha256, version} → esp_ota_begin on the next OTA partition
//   ota_chunk {seq, d:<base64>}       → base64 decode → esp_ota_write
//   ota_end   {sha256}                → esp_ota_end → set_boot_partition → reboot
//
// Anything that fails before set_boot_partition leaves the device booting
// the previous image on next reset. That's the safety story.

static esp_ota_handle_t _otaHandle = 0;
static const esp_partition_t* _otaPartition = nullptr;
static bool _otaActive = false;
static uint32_t _otaTotal = 0;
static uint32_t _otaWritten = 0;
static char _otaExpectedSha[65] = {0};
static mbedtls_sha256_context _otaShaCtx;

static void _otaAck(const char* what, bool ok, uint32_t n = 0, const char* err = nullptr) {
  char b[160];
  int len;
  if (err) {
    len = snprintf(b, sizeof(b),
      "{\"ack\":\"%s\",\"ok\":%s,\"n\":%lu,\"error\":\"%s\"}\n",
      what, ok ? "true" : "false", (unsigned long)n, err);
  } else {
    len = snprintf(b, sizeof(b),
      "{\"ack\":\"%s\",\"ok\":%s,\"n\":%lu}\n",
      what, ok ? "true" : "false", (unsigned long)n);
  }
  Serial.write(b, len);
  bleWrite((const uint8_t*)b, len);
}

// Battery threshold: refuse to start an update if we'd run out of juice
// halfway through. The OTA partition write isn't atomic — losing power
// mid-write doesn't brick the device (boot-partition-switch hasn't
// happened yet) but it does waste bandwidth and frustrate the user.
static bool _otaBatteryOK() {
  if (StickCP2.Power.isCharging()) return true;
  int vBat = StickCP2.Power.getBatteryVoltage();
  int pct = (vBat - 3200) / 10;
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return pct >= 30;
}

static void _otaCleanup(bool aborting) {
  if (_otaHandle && aborting) {
    esp_ota_abort(_otaHandle);
  }
  _otaHandle = 0;
  _otaPartition = nullptr;
  _otaActive = false;
  _otaTotal = 0;
  _otaWritten = 0;
  _otaExpectedSha[0] = 0;
  mbedtls_sha256_free(&_otaShaCtx);
}

// Returns true if the command was an OTA frame (caller skips xferCommand
// and the regular state-update path). Mirrors xferCommand's contract.
inline bool otaCommand(JsonDocument& doc) {
  const char* cmd = doc["cmd"];
  if (!cmd) return false;

  if (strcmp(cmd, "ota_begin") == 0) {
    if (_otaActive) _otaCleanup(true);

    _otaTotal = doc["size"] | 0;
    const char* sha = doc["sha256"] | "";
    strncpy(_otaExpectedSha, sha, sizeof(_otaExpectedSha) - 1);
    _otaExpectedSha[sizeof(_otaExpectedSha) - 1] = 0;

    if (_otaTotal == 0) { _otaAck("ota_begin", false, 0, "size=0"); return true; }
    if (!_otaBatteryOK()) { _otaAck("ota_begin", false, 0, "low_battery"); return true; }

    _otaPartition = esp_ota_get_next_update_partition(NULL);
    if (!_otaPartition) { _otaAck("ota_begin", false, 0, "no_partition"); return true; }
    if (_otaTotal > _otaPartition->size) {
      _otaAck("ota_begin", false, _otaPartition->size, "too_large");
      return true;
    }

    esp_err_t err = esp_ota_begin(_otaPartition, _otaTotal, &_otaHandle);
    if (err != ESP_OK) {
      _otaHandle = 0;
      _otaPartition = nullptr;
      _otaAck("ota_begin", false, 0, esp_err_to_name(err));
      return true;
    }

    mbedtls_sha256_init(&_otaShaCtx);
    mbedtls_sha256_starts(&_otaShaCtx, 0);
    _otaWritten = 0;
    _otaActive = true;
    _otaAck("ota_begin", true, _otaPartition->size);
    return true;
  }

  if (!_otaActive) {
    // No begin → no chunk/end. Don't claim these — the regular dispatch
    // can ignore unknown ota_* commands.
    if (strcmp(cmd, "ota_chunk") == 0 || strcmp(cmd, "ota_end") == 0) {
      _otaAck(cmd, false, 0, "no_session");
      return true;
    }
    return false;
  }

  if (strcmp(cmd, "ota_chunk") == 0) {
    const char* b64 = doc["d"];
    if (!b64) { _otaAck("ota_chunk", false, _otaWritten, "no_data"); return true; }

    uint8_t buf[256];
    size_t outLen = 0;
    int rc = mbedtls_base64_decode(buf, sizeof(buf), &outLen,
                                   (const uint8_t*)b64, strlen(b64));
    if (rc != 0) {
      _otaAck("ota_chunk", false, _otaWritten, "decode_failed");
      _otaCleanup(true);
      return true;
    }

    esp_err_t err = esp_ota_write(_otaHandle, buf, outLen);
    if (err != ESP_OK) {
      _otaAck("ota_chunk", false, _otaWritten, esp_err_to_name(err));
      _otaCleanup(true);
      return true;
    }
    mbedtls_sha256_update(&_otaShaCtx, buf, outLen);
    _otaWritten += outLen;
    _otaAck("ota_chunk", true, _otaWritten);
    return true;
  }

  if (strcmp(cmd, "ota_end") == 0) {
    uint8_t hash[32];
    mbedtls_sha256_finish(&_otaShaCtx, hash);
    char hex[65];
    for (int i = 0; i < 32; i++) snprintf(hex + i*2, 3, "%02x", hash[i]);
    hex[64] = 0;

    if (strcmp(hex, _otaExpectedSha) != 0) {
      _otaAck("ota_end", false, _otaWritten, "hash_mismatch");
      _otaCleanup(true);
      return true;
    }

    esp_err_t err = esp_ota_end(_otaHandle);
    _otaHandle = 0;
    if (err != ESP_OK) {
      _otaAck("ota_end", false, _otaWritten, esp_err_to_name(err));
      _otaCleanup(true);
      return true;
    }

    err = esp_ota_set_boot_partition(_otaPartition);
    if (err != ESP_OK) {
      _otaAck("ota_end", false, _otaWritten, esp_err_to_name(err));
      _otaCleanup(true);
      return true;
    }

    _otaAck("ota_end", true, _otaWritten);
    _otaCleanup(false);
    // Give the ack a moment to flush over BLE/USB before the reset cuts the link.
    delay(250);
    esp_restart();
    return true;
  }

  return false;
}

inline bool otaActive()           { return _otaActive; }
inline uint32_t otaProgress()     { return _otaWritten; }
inline uint32_t otaTotal()        { return _otaTotal; }
