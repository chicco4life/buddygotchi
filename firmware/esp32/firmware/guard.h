#pragma once
#include <Arduino.h>
#include <Preferences.h>
#include <esp_system.h>
#include <esp_task_wdt.h>
#include <esp_attr.h>
#include <esp_ota_ops.h>

// Runtime self-healing: task watchdog, crash-loop breaker, reset telemetry.
//
// Three layers, all designed around "the device ships to customers with no
// serial console":
//
//  1. Task watchdog on loopTask. A wedged loop() (deadlock, blocked BLE
//     callback) becomes a ~30s reboot instead of a dead unit that needs a
//     physical reset. Long-running serial dumps call guardFeed().
//
//  2. Crash-loop breaker. Consecutive crashes that die before reaching
//     GUARD_STABLE_MS of uptime are counted in RTC noinit RAM (survives
//     resets, not power cycles). Tier 1 (>=3): boot without character
//     assets and show a "safe mode" banner — recovers from poisoned
//     character files while keeping BLE up so OTA rescue works. Tier 2
//     (>=6): boot without BLE too — recovers from crashes in the BT stack
//     itself (e.g. the 2026-07 Bluedroid OOM assert) with USB rescue only.
//     Reaching stable uptime clears the counter, so safe mode self-heals
//     on the next reboot. Crashes that recur *after* stable uptime don't
//     accumulate — the breaker targets boot loops specifically; slower
//     crash cycles still reboot via layer 1 and show up in telemetry.
//
//  3. App-level OTA rollback. The bootloader-level rollback config isn't
//     enabled in the prebuilt Arduino IDF libs, so ota.h marks a freshly
//     flashed image "pending" in NVS and the breaker reverts to the
//     previous slot if that image crash-loops before its first stable
//     mark. A bad shipped update becomes a self-healing blip.
//
// Telemetry (lifetime panic count, last reset reason, current tier) is
// exposed via guard*() getters and reported in the ping/state JSON so
// exported bug reports carry it.

static const uint32_t GUARD_WDT_TIMEOUT_S    = 30;
static const uint32_t GUARD_STABLE_MS        = 60000;
static const uint32_t GUARD_SAFE_THRESHOLD   = 3;
static const uint32_t GUARD_BLE_OFF_THRESHOLD = 6;
static const uint32_t GUARD_MAGIC_VALUE      = 0xB00DDA7A;

// RTC noinit: survives esp_restart()/panic resets, garbage on power-on.
RTC_NOINIT_ATTR static uint32_t _guardMagic;
RTC_NOINIT_ATTR static uint32_t _guardEarlyCrashes;

static bool               _guardStable      = false;
static uint32_t           _guardPanicsTotal = 0;
static esp_reset_reason_t _guardReason      = ESP_RST_UNKNOWN;

static bool _guardAbnormal(esp_reset_reason_t r) {
  return r == ESP_RST_PANIC || r == ESP_RST_TASK_WDT ||
         r == ESP_RST_INT_WDT || r == ESP_RST_WDT;
}

inline const char* guardResetReason() {
  switch (_guardReason) {
    case ESP_RST_POWERON:  return "poweron";
    case ESP_RST_SW:       return "sw";
    case ESP_RST_PANIC:    return "panic";
    case ESP_RST_TASK_WDT: return "task_wdt";
    case ESP_RST_INT_WDT:  return "int_wdt";
    case ESP_RST_WDT:      return "wdt";
    case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_DEEPSLEEP:return "deepsleep";
    case ESP_RST_EXT:      return "ext";
    default:               return "unknown";
  }
}

inline uint32_t guardPanicsTotal()  { return _guardPanicsTotal; }
inline uint32_t guardEarlyCrashes() { return _guardEarlyCrashes; }

// 0 = normal, 1 = no character assets, 2 = no BLE either.
inline int guardSafeTier() {
  if (_guardEarlyCrashes >= GUARD_BLE_OFF_THRESHOLD) return 2;
  if (_guardEarlyCrashes >= GUARD_SAFE_THRESHOLD) return 1;
  return 0;
}

// ota.h calls this after esp_ota_set_boot_partition, right before the
// reboot into the new image.
inline void guardNoteOtaPending() {
  Preferences p;
  if (p.begin("guard", false)) {
    p.putBool("otapend", true);
    p.end();
  }
}

// Call once, early in setup() (needs Serial for the breadcrumb, nothing
// else). Decides the safe-mode tier for the rest of setup().
inline void guardInit() {
  _guardReason = esp_reset_reason();
  if (_guardMagic != GUARD_MAGIC_VALUE) {
    // Cold power-on: RTC RAM is garbage. Fresh start.
    _guardMagic = GUARD_MAGIC_VALUE;
    _guardEarlyCrashes = 0;
  }

  Preferences p;
  bool nvsOk = p.begin("guard", false);
  if (nvsOk) _guardPanicsTotal = p.getULong("panics", 0);

  if (_guardAbnormal(_guardReason)) {
    _guardEarlyCrashes++;
    _guardPanicsTotal++;
    if (nvsOk) {
      p.putULong("panics", _guardPanicsTotal);
      p.putULong("lastrr", (uint32_t)_guardReason);
    }
  }

  // Crash-looping on an image that never proved itself: revert to the
  // previous OTA slot. otapend is only true between ota_end and the first
  // stable mark, so an established image never rolls back.
  if (_guardEarlyCrashes >= GUARD_SAFE_THRESHOLD && nvsOk && p.getBool("otapend", false)) {
    const esp_partition_t* running = esp_ota_get_running_partition();
    const esp_partition_t* other = esp_ota_get_next_update_partition(NULL);
    if (running && other && other != running) {
      p.putBool("otapend", false);
      p.end();
      Serial.printf("[guard] crash loop on pending OTA image — rolling back to %s\n", other->label);
      Serial.flush();
      if (esp_ota_set_boot_partition(other) == ESP_OK) esp_restart();
      // Fall through into safe mode if the revert itself failed.
      nvsOk = p.begin("guard", false);
    }
  }
  if (nvsOk) p.end();

  if (_guardAbnormal(_guardReason) || guardSafeTier() > 0) {
    Serial.printf("[guard] reset=%s early=%lu panics=%lu tier=%d\n",
                  guardResetReason(), (unsigned long)_guardEarlyCrashes,
                  (unsigned long)_guardPanicsTotal, guardSafeTier());
  }

  // Watchdog on loopTask (setup()/loop() run on it). panic=true so a hang
  // both reboots and lands in the abnormal-reset telemetry above.
  esp_task_wdt_init(GUARD_WDT_TIMEOUT_S, true);
  esp_task_wdt_add(NULL);
}

// For long-running work inside one loop() pass (screenshot dump, etc.).
inline void guardFeed() { esp_task_wdt_reset(); }

// Call every loop() pass: feeds the watchdog and, once the device has
// stayed up GUARD_STABLE_MS, declares the boot healthy — clears the
// crash-loop counter and accepts a pending OTA image.
inline void guardLoop() {
  esp_task_wdt_reset();
  if (!_guardStable && millis() >= GUARD_STABLE_MS) {
    _guardStable = true;
    _guardEarlyCrashes = 0;
    Preferences p;
    if (p.begin("guard", false)) {
      if (p.getBool("otapend", false)) p.putBool("otapend", false);
      p.end();
    }
  }
}

// Debug/test hook: forget crash history (used by HIL tests so a
// deliberately triggered watchdog reset doesn't push later runs into
// safe mode).
inline void guardClear() {
  _guardEarlyCrashes = 0;
  _guardStable = false;
}
