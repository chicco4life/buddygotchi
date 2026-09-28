// Builds Boop's sound effects (plan/VOICE.md §10) as C arrays, from the
// animation pack's procedural sounds in pack/: its synthesiser and recipes
// (pack/audio/, unchanged) and each design's timeline (pack/scores/, the
// device's states only). The output, firmware/assets/sfx.h, is checked in;
// rerun this only when the pack changes:
//
//     node internal/tools/sfxgen/sfxgen.mjs [--wav-dir DIR]
//
// Each effect the timelines use is rendered once, at the pack's 44.1 kHz,
// then filtered and cut down to 8-bit samples at 11.025 kHz, the voice's
// format. All effects share one scale, so their levels keep the pack's
// balance. The device resamples a clip for an event's pitch, as it does a
// syllable (firmware/src/voice/effects.cpp).
//
// `--wav-dir` also writes every clip as a WAV, for listening.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

import {effects} from './pack/audio/effects.mjs';
import {renderRecipe, SAMPLE_RATE} from './pack/audio/synth.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const out = path.join(root, 'firmware/assets/sfx.h');

// The device's moods and states, in faces.h's order, and each state's
// variations (render/anim.h, render/scene.h). The pack's `listening` has no
// design on the device and is left out.
const moods = ['happy', 'excited', 'proud', 'curious', 'determined', 'grumpy', 'sad'];
const states = ['idle', 'working', 'needs_you', 'task_complete', 'asleep', 'no_app'];
const variants = [3, 5, 3, 3, 3, 3];
const policies = ['silent', 'loop', 'entry', 'sparse'];

const RATE = 11025;
const DOWN = SAMPLE_RATE / RATE;  // 4
const PEAK = 0.70;  // the synthesiser's output stage never goes past this
// An event's loudness is its clip's level times its gain. The pack spans
// about 40 dB, and an 8-bit speaker loses the quiet end in its hiss, so
// the square root squeezes the range and keeps the order: the loudest event
// plays as loud as a syllable, and the quietest about a tenth as loud.
const SQUEEZE = 0.5;

// A windowed-sinc low-pass just under the new Nyquist, so noise and bells
// don't fold back as whistles when every fourth sample is kept.
function lowpass(x) {
  const taps = 63, mid = (taps - 1) / 2, fc = 0.45 / DOWN;
  const h = [];
  for (let i = 0; i < taps; i++) {
    const n = i - mid;
    const sinc = n === 0 ? 2 * fc : Math.sin(2 * Math.PI * fc * n) / (Math.PI * n);
    h.push(sinc * (0.54 - 0.46 * Math.cos((2 * Math.PI * i) / (taps - 1))));
  }
  const y = new Float32Array(Math.ceil(x.length / DOWN));
  for (let j = 0; j < y.length; j++) {
    let acc = 0;
    for (let i = 0; i < taps; i++) {
      const k = j * DOWN + i - mid;
      if (k >= 0 && k < x.length) acc += x[k] * h[i];
    }
    y[j] = acc;
  }
  return y;
}

// A clip at full scale, as the voice's clips are, and how loud it was
// before: the loudness goes into its events' gains instead (below).
function clip(name) {
  const y = lowpass(renderRecipe(effects[name], 1, SAMPLE_RATE));
  const peak = y.reduce((m, v) => Math.max(m, Math.abs(v)), 0) || 1;
  const q = Array.from(y, v => Math.round((v / peak) * 127));
  let end = q.length;
  while (end > 0 && q[end - 1] === 0) end--;  // trailing silence
  return {data: Uint8Array.from(q.slice(0, end), v => 128 + v), level: peak / PEAK};
}

function scoreOf(mood, state, v) {
  const file = path.join(here, 'pack/scores', mood, state, `${mood}.${state}.0${v}.json`);
  const s = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!policies.includes(s.policy)) throw new Error(`${file}: unknown policy ${s.policy}`);
  return s;
}

function writeWav(file, data) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(RATE, 24); h.writeUInt32LE(RATE, 28); h.writeUInt16LE(1, 32); h.writeUInt16LE(8, 34);
  h.write('data', 36); h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(file, Buffer.concat([h, Buffer.from(data)]));
}

function main() {
  const args = process.argv.slice(2);
  const wavDir = args[0] === '--wav-dir' ? args[1] : null;
  if (args.length && !wavDir) {
    console.error('usage: node internal/tools/sfxgen/sfxgen.mjs [--wav-dir DIR]');
    process.exit(2);
  }

  const scores = [];
  for (const mood of moods) for (const [si, state] of states.entries())
    for (let v = 1; v <= variants[si]; v++) scores.push(scoreOf(mood, state, v));
  const names = [...new Set(scores.flatMap(s => s.events.map(e => e.effect)))].sort();
  const made = names.map(clip);
  const clips = made.map(c => c.data);

  const hash = crypto.createHash('sha256');
  for (const dir of ['pack/audio', 'pack/scores']) {
    const walk = d => fs.readdirSync(d, {withFileTypes: true}).sort((a, b) => a.name < b.name ? -1 : 1)
      .forEach(e => e.isDirectory() ? walk(path.join(d, e.name)) : hash.update(fs.readFileSync(path.join(d, e.name))));
    walk(path.join(here, dir));
  }
  hash.update(fs.readFileSync(fileURLToPath(import.meta.url)));
  const version = hash.digest('hex').slice(0, 12);

  const bytes = clips.reduce((n, c) => n + c.length, 0);
  const L = [];
  L.push(`// Boop's sound effects: 8-bit unsigned samples at 11.025 kHz (plan/VOICE.md §10).`);
  L.push(`// Generated by internal/tools/sfxgen/sfxgen.mjs from the animation pack's sounds.`);
  L.push(`// Don't edit; rerun the tool. Include from one .cpp only (voice/effects.cpp).`);
  L.push('#pragma once', '#include <cstdint>', '', 'namespace sfx_assets {', '');
  L.push(`constexpr uint32_t kRate = ${RATE};`);
  L.push(`constexpr const char* kVersion = "${version}";`);
  L.push(`constexpr int kClips = ${clips.length};`);
  L.push(`constexpr uint32_t kBytes = ${bytes};`);
  L.push(`constexpr int kMoods = ${moods.length};`, `constexpr int kStates = ${states.length};`);
  L.push(`static const uint8_t kVariants[kStates] = {${variants.join(', ')}};`, '');
  L.push('struct Clip {', '  const char* name;', '  uint32_t at;   // offset into kSamples',
    '  uint16_t len;  // samples', '  bool alert;    // the needs-you signal: a mumble never turns it down', '};', '');
  L.push('static const Clip kClip[] = {');
  let at = 0;
  names.forEach((n, i) => { L.push(`    {"${n}", ${at}, ${clips[i].length}, ${n.startsWith('alert')}},`); at += clips[i].length; });
  L.push('};', '');
  L.push('// When a design\'s events play: never, every loop, its first loop only, or', '// its first loop and then at most once per `intervalMs`.');
  L.push('enum Policy : uint8_t { kSilent, kLoop, kEntry, kSparse };', '');
  L.push('struct Event {', '  uint16_t atMs;   // into the design\'s loop', '  uint8_t clip;',
    '  uint8_t gain;    // 1–255: 255 plays the clip as loud as a syllable', '  uint16_t pitch;  // permille: 1000 plays the clip as made', '};', '');
  L.push('struct Score {', '  Policy policy;', '  uint32_t intervalMs;', '  uint16_t first;  // into kEvent', '  uint8_t n;', '};', '');
  const loud = e => made[names.indexOf(e.effect)].level * (e.gain ?? 1);
  const loudest = Math.max(...scores.flatMap(s => s.events.map(loud)));
  const events = [], rows = [];
  for (const s of scores) {
    const evs = s.events.map(e => ({
      at: Math.round(e.at * 1000), clip: names.indexOf(e.effect),
      gain: Math.max(1, Math.round(255 * Math.pow(loud(e) / loudest, SQUEEZE))), pitch: Math.round((e.pitch ?? 1) * 1000),
    })).sort((a, b) => a.at - b.at || a.clip - b.clip);
    if (s.policy === 'silent') evs.length = 0;
    if (evs.length > 255) throw new Error(`${s.id}: too many events`);
    rows.push(`    {k${s.policy[0].toUpperCase()}${s.policy.slice(1)}, ${Math.round((s.intervalSeconds || 0) * 1000)}, ${events.length}, ${evs.length}},  // ${s.id}`);
    events.push(...evs);
  }
  L.push('// Every design\'s timeline, by mood, then state, then variation.');
  L.push('static const Score kScore[] = {', ...rows, '};', '');
  L.push('static const Event kEvent[] = {');
  for (let i = 0; i < events.length; i += 6)
    L.push('    ' + events.slice(i, i + 6).map(e => `{${e.at}, ${e.clip}, ${e.gain}, ${e.pitch}}`).join(', ') + ',');
  L.push('};', '');
  const blob = Buffer.concat(clips.map(c => Buffer.from(c)));
  L.push('static const uint8_t kSamples[] = {');
  for (let i = 0; i < blob.length; i += 32) L.push('    ' + Array.from(blob.subarray(i, i + 32)).join(',') + ',');
  L.push('};', '', '}  // namespace sfx_assets', '');
  fs.writeFileSync(out, L.join('\n'));
  console.log(`sfxgen: ${clips.length} clips, ${(bytes / 1024).toFixed(0)} KB, ${events.length} events in ${scores.length} timelines, version ${version}`);

  if (wavDir) {
    fs.mkdirSync(wavDir, {recursive: true});
    names.forEach((n, i) => writeWav(path.join(wavDir, `${n}.wav`), clips[i]));
  }
}

main();
