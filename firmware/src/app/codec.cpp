#include "app/codec.h"

namespace app {

uint32_t crc32(const uint8_t* data, size_t n, uint32_t crc) {
  crc = ~crc;
  for (size_t i = 0; i < n; ++i) {
    crc ^= data[i];
    for (int k = 0; k < 8; ++k) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
  }
  return ~crc;
}

static const char kAlphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

void Base64Writer::write(const uint8_t* data, size_t n) {
  for (size_t i = 0; i < n; ++i) {
    pend_[npend_++] = data[i];
    if (npend_ < 3) continue;
    uint32_t v = (uint32_t(pend_[0]) << 16) | (uint32_t(pend_[1]) << 8) | pend_[2];
    out_[nout_++] = kAlphabet[(v >> 18) & 63];
    out_[nout_++] = kAlphabet[(v >> 12) & 63];
    out_[nout_++] = kAlphabet[(v >> 6) & 63];
    out_[nout_++] = kAlphabet[v & 63];
    npend_ = 0;
    if (nout_ + 4 > sizeof(out_)) flushOut();
  }
}

void Base64Writer::finish() {
  if (npend_ > 0) {
    uint32_t v = uint32_t(pend_[0]) << 16;
    if (npend_ > 1) v |= uint32_t(pend_[1]) << 8;
    out_[nout_++] = kAlphabet[(v >> 18) & 63];
    out_[nout_++] = kAlphabet[(v >> 12) & 63];
    out_[nout_++] = npend_ > 1 ? kAlphabet[(v >> 6) & 63] : '=';
    out_[nout_++] = '=';
    npend_ = 0;
  }
  flushOut();
}

void Base64Writer::flushOut() {
  if (nout_) sink_(ctx_, out_, nout_);
  nout_ = 0;
}

}  // namespace app
