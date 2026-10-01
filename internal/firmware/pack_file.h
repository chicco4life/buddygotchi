// The voice pack from a file (documentation/VOICE.md §8), for the simulator and the
// firmware's tests, which have no SD card: .build/voice/voice.bin, which
// `make -C internal voice` builds (voicegen).
#pragma once
#include <cstdio>
#include <string>

#include "voice/player.h"

namespace packfile {

struct FileSource : voice::Source {
  std::FILE* f = nullptr;
  bool read(uint32_t at, void* buf, uint32_t n) override {
    return f && !std::fseek(f, long(at), SEEK_SET) && std::fread(buf, 1, n, f) == n;
  }
};

// The repo's pack file, found from this file's own path.
inline FileSource& source() {
  static FileSource src;
  if (!src.f) {
    std::string here = __FILE__;  // <repo>/internal/firmware/pack_file.h
    std::string repo = here.substr(0, here.rfind("/internal/firmware/"));
    src.f = std::fopen((repo + "/.build/voice/voice.bin").c_str(), "rb");
  }
  return src;
}

// Opens it as the voice pack; false when it hasn't been built.
inline bool open() { return source().f && voice::openPack(&source()); }

}  // namespace packfile
