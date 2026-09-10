#include "ble_bridge.h"
#ifdef BOOP_USB_ONLY
// Bench-only build: never initialize, advertise, or touch the bond store.
void bleInit(const char*) {}
void bleStop() {}
bool bleConnected() { return false; }
bool bleSecure() { return false; }
uint32_t blePasskey() { return 0; }
void bleClearBonds() {}
// Render the adopted-device UI for bench frames without opening bond storage.
bool bleBonded() { return true; }
size_t bleAvailable() { return 0; }
int bleRead() { return -1; }
size_t bleWrite(const uint8_t*, size_t) { return 0; }
uint32_t bleRxDropped() { return 0; }
uint32_t bleLinkGeneration() { return 0; }
#else
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLESecurity.h>
#include <BLE2902.h>
#include <Arduino.h>
#include <string.h>
// Arduino core 2.x (M5 board) backs this library with Bluedroid; core 3.x
// (S3 board) backs it with NimBLE behind the same classes. The few places
// the backends genuinely diverge — auth-complete callback shape, encryption
// enforcement, bond clearing — are #if'd on CONFIG_BLUEDROID_ENABLED below.
#if defined(CONFIG_NIMBLE_ENABLED)
#include <host/ble_store.h>
#endif

// Nordic UART Service UUIDs — every BLE serial example uses these, so
// existing tools (nRF Connect, bluefy, Web Bluetooth examples) can talk to
// us without custom UUIDs.
#define NUS_SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_RX_UUID      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_TX_UUID      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

// Incoming bytes are buffered in a simple ring for bleRead()/bleAvailable().
// Sized to hold a transcript snapshot JSON plus headroom; the GATT layer
// will flow-control if we fall behind.
//
// The ring is produced on the Bluetooth host task and consumed on the
// Arduino loop task — two different cores. volatile alone gives no
// ordering guarantee there, so every access goes through rxMux. Overflow
// drops are counted (not silent): a dropped byte truncates a JSON line
// into a parse failure, and the counter in `state` is the only way to
// see that happened.
static const size_t RX_CAP = 2048;
static uint8_t  rxBuf[RX_CAP];
static size_t   rxHead = 0;
static size_t   rxTail = 0;
static uint32_t rxDropped = 0;
static portMUX_TYPE rxMux = portMUX_INITIALIZER_UNLOCKED;

static BLEServer*         server = nullptr;
static BLECharacteristic* txChar = nullptr;
static BLECharacteristic* rxChar = nullptr;
// Bumped on every disconnect. Consumers that assemble bytes into lines watch
// this so a fragment from a dead link can't be glued onto the next one.
static volatile uint32_t  linkGen = 0;
static volatile bool      connected = false;
static volatile bool      secure = false;
static volatile uint32_t  passkey = 0;
static volatile uint16_t  mtu = 23;

static void rxPush(const uint8_t* p, size_t n) {
  portENTER_CRITICAL(&rxMux);
  for (size_t i = 0; i < n; i++) {
    size_t next = (rxHead + 1) % RX_CAP;
    if (next == rxTail) {        // full — count the loss, drop the rest
      rxDropped += (uint32_t)(n - i);
      break;
    }
    rxBuf[rxHead] = p[i];
    rxHead = next;
  }
  portEXIT_CRITICAL(&rxMux);
}

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    // getValue() returns std::string on core 2.x, Arduino String on 3.x;
    // c_str()/length() are the common surface.
    auto v = c->getValue();
    if (v.length()) rxPush((const uint8_t*)v.c_str(), v.length());
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    connected = true;
    Serial.println("[ble] connected");
  }
#if !defined(CONFIG_BLUEDROID_ENABLED)
  // NimBLE (S3 board): ask the central for a 15-30 ms connection interval
  // (units of 1.25 ms; macOS accepts 15 ms and defaults to ~30 ms otherwise).
  // Every frame chunk costs at least one interval, so this is most of the
  // hook-to-card budget. Latency 0, supervision timeout 4 s (units of 10 ms).
  void onConnect(BLEServer* s, ble_gap_conn_desc* desc) override {
    onConnect(s);
    s->updateConnParams(desc->conn_handle, 12, 24, 0, 400);
  }
#endif
  void onDisconnect(BLEServer* s) override {
    connected = false;
    secure = false;
    passkey = 0;
    mtu = 23;
    // Drop whatever was mid-flight. A link that dies partway through a
    // chunked heartbeat leaves a headless fragment in the ring; the next
    // connection's first frame (the one-shot time sync) would be appended to
    // it, fail to parse, and be lost — taking the clock with it, since
    // nothing re-sends it. The desktop clears its own RX buffer on
    // disconnect for the same reason.
    portENTER_CRITICAL(&rxMux);
    rxHead = 0;
    rxTail = 0;
    portEXIT_CRITICAL(&rxMux);
    linkGen++;   // tells the line assembler in data.h to drop its fragment
    Serial.println("[ble] disconnected");
    // Restart advertising so the next client can find us.
    BLEDevice::startAdvertising();
  }
#if defined(CONFIG_BLUEDROID_ENABLED)
  void onMtuChanged(BLEServer*, esp_ble_gatts_cb_param_t* param) override {
    mtu = param->mtu.mtu;
    Serial.printf("[ble] mtu=%u\n", mtu);
  }
#else
  void onMtuChanged(BLEServer*, ble_gap_conn_desc*, uint16_t newMtu) override {
    mtu = newMtu;
    Serial.printf("[ble] mtu=%u\n", mtu);
  }
#endif
};

// LE Secure Connections, passkey-entry: we are DisplayOnly, the central
// is KeyboardOnly. The stack picks a random 6-digit passkey, calls
// onPassKeyNotify here, and the user types it on the desktop. main.cpp
// polls blePasskey() to render it.
class SecCallbacks : public BLESecurityCallbacks {
  uint32_t onPassKeyRequest() override { return 0; }
  bool onConfirmPIN(uint32_t) override { return false; }
  bool onSecurityRequest() override { return true; }
  void onPassKeyNotify(uint32_t pk) override {
    passkey = pk;
    Serial.printf("[ble] passkey %06lu\n", (unsigned long)pk);
  }
#if defined(CONFIG_BLUEDROID_ENABLED)
  void onAuthenticationComplete(esp_ble_auth_cmpl_t cmpl) override {
    passkey = 0;
    secure = cmpl.success;
    Serial.printf("[ble] auth %s\n", cmpl.success ? "ok" : "FAIL");
    if (!cmpl.success && server) server->disconnect(server->getConnId());
  }
#else
  void onAuthenticationComplete(ble_gap_conn_desc* desc) override {
    passkey = 0;
    bool ok = desc && desc->sec_state.encrypted && desc->sec_state.authenticated;
    secure = ok;
    Serial.printf("[ble] auth %s\n", ok ? "ok" : "FAIL");
    if (!ok && server) server->disconnect(server->getConnId());
  }
#endif
};

void bleInit(const char* deviceName) {
  BLEDevice::init(deviceName);
  // Request the biggest MTU we can get. macOS negotiates to 185 typically.
  BLEDevice::setMTU(517);

#if defined(CONFIG_BLUEDROID_ENABLED)
  BLEDevice::setEncryptionLevel(ESP_BLE_SEC_ENCRYPT_MITM);
#else
  // NimBLE path: characteristic-level encrypted-access permissions plus
  // forced authentication play the same role as Bluedroid's link-level
  // encryption requirement.
  BLESecurity::setForceAuthentication(true);
#endif
  BLEDevice::setSecurityCallbacks(new SecCallbacks());

  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* svc = server->createService(NUS_SERVICE_UUID);

  txChar = svc->createCharacteristic(
    NUS_TX_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  txChar->setAccessPermissions(ESP_GATT_PERM_READ_ENCRYPTED);
  BLE2902* cccd = new BLE2902();
  cccd->setAccessPermissions(ESP_GATT_PERM_READ_ENCRYPTED | ESP_GATT_PERM_WRITE_ENCRYPTED);
  txChar->addDescriptor(cccd);

  rxChar = svc->createCharacteristic(
    NUS_RX_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  rxChar->setAccessPermissions(ESP_GATT_PERM_WRITE_ENCRYPTED);
  rxChar->setCallbacks(new RxCallbacks());

  svc->start();

  BLESecurity* sec = new BLESecurity();
  sec->setAuthenticationMode(ESP_LE_AUTH_REQ_SC_MITM_BOND);
  sec->setCapability(ESP_IO_CAP_OUT);
  sec->setKeySize(16);
  sec->setInitEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);
  sec->setRespEncryptionKey(ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK);

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(NUS_SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);   // iOS-friendly connection interval
  adv->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.printf("[ble] advertising as '%s'\n", deviceName);
}

void bleStop() {
  // Pre-sleep quiesce only: stop advertising so no new central starts a
  // connect/auth dance while we're going down. Deliberately NOT
  // BLEDevice::deinit — freeing host structures under a live link
  // corrupts the heap on the NimBLE-backed core-3 wrapper (proven on
  // hardware: the Mac re-authed mid-teardown and the next free()
  // panicked). The HAL disables the BT *controller* right before sleep,
  // and the caller esp_restart()s on wake, so nothing here leaks.
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  if (adv) adv->stop();
}

bool bleConnected() { return connected; }
bool bleSecure()    { return secure; }
uint32_t blePasskey() { return passkey; }

// bleBonded()'s cache. File-scope so bleClearBonds can invalidate it —
// otherwise an "unpair" would keep reporting adopted for up to 2s and the
// pair-me screen would arrive late.
static bool     _bondCached = false;
static uint32_t _bondCheckedAt = 0;

void bleClearBonds() {
  _bondCheckedAt = 0;
#if defined(CONFIG_BLUEDROID_ENABLED)
  // Arduino core 2.x (M5 board): Bluedroid host, per-device bond removal.
  int n = esp_ble_get_bond_device_num();
  if (n <= 0) return;
  esp_ble_bond_dev_t* list = (esp_ble_bond_dev_t*)malloc(n * sizeof(esp_ble_bond_dev_t));
  if (!list) return;
  esp_ble_get_bond_device_list(&n, list);
  for (int i = 0; i < n; i++) esp_ble_remove_bond_device(list[i].bd_addr);
  free(list);
  Serial.printf("[ble] cleared %d bond(s)\n", n);
#else
  // Arduino core 3.x (S3 board): the BLE library is NimBLE-backed; the
  // store API wipes bonds, CCCDs, and peer records in one call.
  ble_store_clear();
  Serial.println("[ble] cleared bond store");
#endif
}

// Counting bonds walks the NVS-backed store, so the answer is cached and
// refreshed at most every 2s. The draw path asks every frame (it routes
// pair-me vs nap), and a bond only ever appears at pairing time or vanishes
// on an explicit clear — both far slower than the refresh interval.
bool bleBonded() {
  uint32_t now = millis();
  if (_bondCheckedAt != 0 && (now - _bondCheckedAt) < 2000) return _bondCached;
  _bondCheckedAt = now == 0 ? 1 : now;
  bool& cached = _bondCached;
#if defined(CONFIG_BLUEDROID_ENABLED)
  cached = esp_ble_get_bond_device_num() > 0;
#elif defined(CONFIG_NIMBLE_ENABLED)
  int count = 0;
  cached = (ble_store_util_count(BLE_STORE_OBJ_TYPE_PEER_SEC, &count) == 0) && count > 0;
#else
  // Unknown host stack: claim adopted. Failing this way keeps a working
  // device quiet (nap) rather than nagging a paired user to pair again.
  cached = true;
#endif
  return cached;
}

size_t bleAvailable() {
  portENTER_CRITICAL(&rxMux);
  size_t n = (rxHead + RX_CAP - rxTail) % RX_CAP;
  portEXIT_CRITICAL(&rxMux);
  return n;
}

int bleRead() {
  portENTER_CRITICAL(&rxMux);
  int b = -1;
  if (rxHead != rxTail) {
    b = rxBuf[rxTail];
    rxTail = (rxTail + 1) % RX_CAP;
  }
  portEXIT_CRITICAL(&rxMux);
  return b;
}

uint32_t bleRxDropped() {
  portENTER_CRITICAL(&rxMux);
  uint32_t n = rxDropped;
  portEXIT_CRITICAL(&rxMux);
  return n;
}

uint32_t bleLinkGeneration() { return linkGen; }

size_t bleWrite(const uint8_t* data, size_t len) {
  if (!connected || !txChar) return 0;
  // ATT notify payload is limited to (MTU - 3). macOS negotiates 185, so
  // the 182-byte chunk works there; use the live mtu so a peer that caps
  // at the 23-byte default doesn't get truncated notifies.
  size_t chunk = mtu > 3 ? mtu - 3 : 20;
  if (chunk > 180) chunk = 180;
  size_t sent = 0;
  while (sent < len) {
    size_t n = len - sent;
    if (n > chunk) n = chunk;
    txChar->setValue((uint8_t*)(data + sent), n);
    txChar->notify();
    sent += n;
    // Small yield so the BLE stack flushes before the next chunk.
    delay(4);
  }
  return sent;
}

#endif // BOOP_USB_ONLY
