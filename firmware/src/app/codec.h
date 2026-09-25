// Screenshot encoding helpers: CRC-32 and streaming base64. Pure C++.
#pragma once
#include <cstddef>
#include <cstdint>

namespace app {

// CRC-32 (IEEE 802.3, as zlib.crc32). Pass the previous result to continue.
uint32_t crc32(const uint8_t* data, size_t n, uint32_t crc = 0);

// Encodes a byte stream as one base64 string, chunk by chunk. `sink` gets
// the text as it's produced; call finish() once at the end.
class Base64Writer {
 public:
  using Sink = void (*)(void* ctx, const char* text, size_t n);
  Base64Writer(Sink sink, void* ctx) : sink_(sink), ctx_(ctx) {}
  void write(const uint8_t* data, size_t n);
  void finish();

 private:
  void flushOut();
  Sink sink_;
  void* ctx_;
  uint8_t pend_[3] = {};
  int npend_ = 0;
  char out_[256];
  size_t nout_ = 0;
};

}  // namespace app
