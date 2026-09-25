#include "link/ble.h"

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <esp_bt.h>
#include <esp_mac.h>

#include <atomic>
#include <cstdio>

namespace links {

namespace {

// The Nordic UART Service: RX is written by the Mac, TX notifies it.
constexpr const char* kService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr const char* kRx = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
constexpr const char* kTx = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

// Written by the Bluetooth task, read by the main loop.
app::ByteRing<2048> rxRing;
std::atomic<bool> linkUp{false};
std::atomic<uint32_t> connects{0};     // bumps on every connect and disconnect,
std::atomic<uint16_t> mtu{23};         // so the loop never misses a quick pair
NimBLECharacteristic* tx = nullptr;

class ServerEvents : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    mtu = 23;
    linkUp = true;
    ++connects;
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    linkUp = false;
    ++connects;
    // advertiseOnDisconnect (the default) starts advertising again.
  }
  void onMTUChange(uint16_t m, NimBLEConnInfo&) override { mtu = m; }
};

class RxEvents : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
    NimBLEAttValue v = c->getValue();
    rxRing.put(v.data(), v.length());
  }
};

ServerEvents serverEvents;
RxEvents rxEvents;
uint32_t seenConnects = 0;

}  // namespace

Ble::Ble() : out_(sendPacket, this) {}

bool Ble::begin() {
  uint8_t mac[6] = {};
  esp_read_mac(mac, ESP_MAC_BT);
  std::snprintf(name_, sizeof(name_), "Boop-%02X%02X", mac[4], mac[5]);
  std::snprintf(id_, sizeof(id_), "b00p-%02x%02x", mac[4], mac[5]);

  // Boop only uses BLE: give Classic Bluetooth's memory back to the heap.
  esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT);
  if (!NimBLEDevice::init(name_)) return false;
  NimBLEDevice::setMTU(247);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(&serverEvents, false);
  NimBLEService* svc = server->createService(kService);
  tx = svc->createCharacteristic(kTx, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* rx = svc->createCharacteristic(kRx, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  rx->setCallbacks(&rxEvents);
  svc->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->setName(name_);
  adv->addServiceUUID(kService);
  adv->enableScanResponse(true);
  started_ = adv->start();
  return started_;
}

bool Ble::poll(app::Device& device) {
  if (!started_) return false;
  uint32_t c = connects.load();
  if (c != seenConnects) {
    seenConnects = c;
    bool up = linkUp.load();
    if (connected_) {
      device.disconnected(app::Link::kBle);
      connected_ = false;
    }
    line_ = app::LineReader{};
    out_.clear();
    if (up) {
      connected_ = true;
      device.connected(app::Link::kBle);  // sends status
    }
  }
  if (connected_) {
    uint16_t m = mtu.load();
    out_.setPayload(m > 3 ? m - 3 : 20);
  }
  uint8_t b;
  while (rxRing.take(b)) {
    if (line_.feed(char(b))) {
      device.handleLine(line_.line(), line_.length(), app::Link::kBle);
      return true;
    }
  }
  return false;
}

void Ble::write(const char* s, size_t n) {
  if (connected_ && linkUp.load()) out_.write(s, n);
}

void Ble::sendPacket(void*, const uint8_t* data, size_t n) {
  // Notifications queue in NimBLE's buffers; if they're full, give the
  // controller a moment and try again, then drop the packet.
  for (int i = 0; i < 20; ++i) {
    if (tx->notify(data, n)) return;
    if (!linkUp.load()) return;
    delay(2);
  }
}

const char* Ble::state() const {
  if (!started_) return "off";
  return linkUp.load() ? "conn" : "adv";
}

uint32_t Ble::dropped() const { return rxRing.dropped(); }

}  // namespace links
