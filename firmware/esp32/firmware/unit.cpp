#include "unit.h"
#include <Arduino.h>
#include <Preferences.h>
#include <bootloader_random.h>
#include <esp_random.h>
#include <mbedtls/base64.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/ecdsa.h>
#include <mbedtls/platform_util.h>
#include <mbedtls/sha256.h>
#include <mbedtls/version.h>
// mbedTLS 3 (S3 board, Arduino core 3.x) hides struct fields behind
// MBEDTLS_PRIVATE; mbedTLS 2 (M5 boards, core 2.x) exposes them directly.
#include <mbedtls/version.h>
#ifndef MBEDTLS_PRIVATE
#define MBEDTLS_PRIVATE(member) member
#endif
#if MBEDTLS_VERSION_MAJOR < 3
// mbedTLS 2's mbedtls_sha256 returns void; the int-returning form is _ret.
#define mbedtls_sha256 mbedtls_sha256_ret
#endif

// Shipped mbedTLS has no Ed25519 pk type. P-256 public keys use SEC1
// uncompressed encoding; signatures are ASN.1 DER ECDSA over SHA-256.
namespace {
char identity[17] = "", public64[96] = "";   // base64 of 65 bytes = 88 chars + NUL
uint32_t keygenMs = 0, lastSign = 0;
const char* failStage = "";   // where setup gave up; surfaced in ping for diagnosis
bool ready = false, attempted = false, rngReady = false;
mbedtls_ctr_drbg_context rng;
int entropy(void*, unsigned char* out, size_t len) {
  while (len) {
    uint32_t word = esp_random();
    size_t n = len < sizeof(word) ? len : sizeof(word);
    memcpy(out, &word, n); out += n; len -= n;
  }
  return 0;
}
bool encode(const uint8_t* bytes, size_t len, char* out, size_t capacity) {
  size_t written = 0;
  // mbedTLS wants room for its own NUL: pass the full capacity.
  if (mbedtls_base64_encode((unsigned char*)out, capacity, &written, bytes, len)) return false;
  out[written] = 0; return true;
}
void error(JsonDocument& d, const char* text) { d["ok"] = false; d["error"] = text; }
bool load(Preferences& p, mbedtls_ecdsa_context& key, uint8_t* pub) {
  uint8_t secret[32] = {};
  bool ok = p.getBytesLength("private") == sizeof(secret) &&
    p.getBytesLength("public") == 65 && p.getBytes("private", secret, sizeof(secret)) == sizeof(secret) &&
    p.getBytes("public", pub, 65) == 65;
  if (ok) ok = !mbedtls_ecp_group_load(&key.MBEDTLS_PRIVATE(grp), MBEDTLS_ECP_DP_SECP256R1) &&
    !mbedtls_mpi_read_binary(&key.MBEDTLS_PRIVATE(d), secret, sizeof(secret)) &&
    !mbedtls_ecp_check_privkey(&key.MBEDTLS_PRIVATE(grp), &key.MBEDTLS_PRIVATE(d)) &&
    !mbedtls_ecp_point_read_binary(&key.MBEDTLS_PRIVATE(grp), &key.MBEDTLS_PRIVATE(Q), pub, 65) &&
    !mbedtls_ecp_check_pubkey(&key.MBEDTLS_PRIVATE(grp), &key.MBEDTLS_PRIVATE(Q));
  mbedtls_platform_zeroize(secret, sizeof(secret));
  return ok;
}
}

void unitSetup() {
  mbedtls_ctr_drbg_init(&rng);
  // Enable the hardware noise source BEFORE HAL starts ADC and BLE starts RF.
  bootloader_random_enable();
  const unsigned char personalization[] = "boop-unit-p256-v1";
  rngReady = !mbedtls_ctr_drbg_seed(&rng, entropy, nullptr, personalization, sizeof(personalization)-1);
  bootloader_random_disable();
  if (!rngReady) { failStage = "rng"; return; }
  // Subsequent requests use the seeded DRBG, including in BLE-disabled safe mode.
  mbedtls_ctr_drbg_set_reseed_interval(&rng, INT_MAX);
  Preferences p;
  if (!p.begin("unit", false)) { failStage = "nvs"; return; }
  mbedtls_ecdsa_context key; mbedtls_ecdsa_init(&key);
  uint8_t pub[65] = {}, secret[32] = {};
  bool ok;
  if (!p.isKey("private") && !p.isKey("public")) {
    uint32_t start = millis();
    size_t size = 0;
    ok = !mbedtls_ecdsa_genkey(&key, MBEDTLS_ECP_DP_SECP256R1, mbedtls_ctr_drbg_random, &rng) &&
      !mbedtls_mpi_write_binary(&key.MBEDTLS_PRIVATE(d), secret, sizeof(secret)) &&
      !mbedtls_ecp_point_write_binary(&key.MBEDTLS_PRIVATE(grp), &key.MBEDTLS_PRIVATE(Q),
        MBEDTLS_ECP_PF_UNCOMPRESSED, &size, pub, sizeof(pub)) && size == sizeof(pub);
    // Private blob is authoritative; an interrupted two-blob write fails closed
    // on next boot instead of silently changing an established identity.
    if (ok) ok = p.putBytes("private", secret, sizeof(secret)) == sizeof(secret) &&
                 p.putBytes("public", pub, sizeof(pub)) == sizeof(pub);
    // A fast keygen can round to 0 ms; report at least 1 so "a key was made" is visible.
    keygenMs = millis()-start; if (keygenMs == 0) keygenMs = 1;
    if (!ok) failStage = "genkey_or_put";
  } else {
    ok = load(p, key, pub);
    if (!ok) failStage = "load";
    // Check that persisted public and private blobs actually belong together.
    mbedtls_ecp_point derived; mbedtls_ecp_point_init(&derived);
    if (ok) ok = !mbedtls_ecp_mul(&key.MBEDTLS_PRIVATE(grp), &derived,
      &key.MBEDTLS_PRIVATE(d), &key.MBEDTLS_PRIVATE(grp).G, mbedtls_ctr_drbg_random, &rng) &&
      !mbedtls_ecp_point_cmp(&derived, &key.MBEDTLS_PRIVATE(Q));
    mbedtls_ecp_point_free(&derived);
    if (!ok && !failStage[0]) failStage = "derive";
  }
  p.end(); mbedtls_platform_zeroize(secret, sizeof(secret)); mbedtls_ecdsa_free(&key);
  uint8_t digest[32];
  if (ok) { ok = !mbedtls_sha256(pub, sizeof(pub), digest, 0) && encode(pub, sizeof(pub), public64, sizeof(public64)); if (!ok) failStage = "sha_or_encode"; }
  if (ok) {
    for (int i=0; i<8; ++i) snprintf(identity+i*2, 3, "%02x", digest[i]);
    ready = true;
  }
}

bool unitClear() {
  ready = false; identity[0] = public64[0] = 0;
  Preferences p;
  if (!p.begin("unit", false)) return false;
  bool ok = p.clear(); p.end(); return ok;
}
const char* unitId() { return identity; }
uint32_t unitKeygenMs() { return keygenMs; }
const char* unitFailStage() { return failStage; }
void unitReply(JsonDocument& d) {
  d["ack"] = "unit";
  if (!ready) { error(d, "key_unavailable_reboot"); return; }
  d["ok"] = true; d["unit"] = identity; d["pub"] = public64; d["alg"] = "p256";
}
void unitSign(JsonDocument& request, JsonDocument& d) {
  d["ack"] = "sign";
  auto dayValue = request["day"].as<JsonString>();
  const char* day = dayValue.c_str();
  if (!day || dayValue.size()!=10) { error(d, "invalid_day"); return; }
  for (int i=0; i<10; ++i) {
    if ((i==4 || i==7) ? day[i]!='-' : (day[i]<'0' || day[i]>'9')) {
      error(d, "invalid_day"); return;
    }
  }
  if (!request["xp"].is<int64_t>() || request["xp"].as<int64_t>()<0) { error(d, "invalid_xp"); return; }
  auto nonceValue = request["nonce"].as<JsonString>();
  const char* nonce = nonceValue.c_str();
  if (!nonce || !nonceValue.size() || nonceValue.size()>64 || nonceValue.size()%2) { error(d, "invalid_nonce"); return; }
  for (size_t i=0; i<nonceValue.size(); ++i) {
    char c = nonce[i];
    if (!((c>='0' && c<='9') || (c>='a' && c<='f') || (c>='A' && c<='F'))) { error(d, "invalid_nonce"); return; }
  }
  if (!ready || !rngReady) { error(d, "key_unavailable_reboot"); return; }
  uint32_t now = millis(); // Real clock; frozen animation time cannot bypass this.
  if (attempted && uint32_t(now-lastSign)<1000) { error(d, "rate_limited"); return; }
  attempted = true; lastSign = now; // Gate crypto failures as well as successes.
  int64_t xp = request["xp"].as<int64_t>();
  char message[128];
  int length = snprintf(message, sizeof(message), "%s|%s|%lld|%s", identity, day, (long long)xp, nonce);
  uint8_t digest[32], sig[MBEDTLS_ECDSA_MAX_LEN], pub[65]; size_t sigLen = 0;
  mbedtls_ecdsa_context key; mbedtls_ecdsa_init(&key);
  Preferences p;
  bool ok = length>0 && size_t(length)<sizeof(message) && p.begin("unit", true);
  if (ok) { ok = load(p, key, pub); p.end(); }
  if (ok) ok = !mbedtls_sha256((const unsigned char*)message, length, digest, 0) &&
#if MBEDTLS_VERSION_MAJOR < 3
    !mbedtls_ecdsa_write_signature(&key, MBEDTLS_MD_SHA256, digest, sizeof(digest),
      sig, &sigLen, mbedtls_ctr_drbg_random, &rng);
#else
    !mbedtls_ecdsa_write_signature(&key, MBEDTLS_MD_SHA256, digest, sizeof(digest),
      sig, sizeof(sig), &sigLen, mbedtls_ctr_drbg_random, &rng);
#endif
  mbedtls_ecdsa_free(&key); // Private scalar exists in RAM only while crypto runs.
  char encoded[101];
  if (!ok || !encode(sig, sigLen, encoded, sizeof(encoded))) { error(d, "sign_failed"); return; }
  d["ok"] = true; d["unit"] = identity; d["day"] = day; d["xp"] = xp;
  d["nonce"] = nonce; d["sig"] = encoded;
}
