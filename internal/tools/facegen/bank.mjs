// Exports the animation bank's designs for facegen.py, which runs this:
// every design's SVG, made by the bank's own generator
// (internal/boop-design/boop-sound-bank-v4/runtime/), into DIR/svg/, and
// its catalogue entry, with its voice window, into DIR/designs.json. DIR is
// ignored by git; the bank is the designs' only source (plan/DEVICE.md §6).
//
//     node internal/tools/facegen/bank.mjs --out DIR
import fs from 'node:fs';
import path from 'node:path';

import {effects} from '../../boop-design/boop-sound-bank-v4/runtime/audio/effects.mjs';
import {catalog} from '../../boop-design/boop-sound-bank-v4/runtime/catalog.mjs';
import {makeScene} from '../../boop-design/boop-sound-bank-v4/runtime/bank.mjs';
import {protectedSoundStates} from '../../boop-design/boop-sound-bank-v4/runtime/quiet-mix.mjs';

const args = process.argv.slice(2);
if (args.length !== 2 || args[0] !== '--out') {
  console.error('usage: node internal/tools/facegen/bank.mjs --out DIR');
  process.exit(2);
}
const out = path.resolve(args[1]);
fs.rmSync(path.join(out, 'svg'), {recursive: true, force: true});

// The bank's three kinds of SVG: V2, the first pack (no renderer); V3, the
// older moods' newer states; V4, the new moods' flip-books.
const dialects = {undefined: 'v2', 'state-v3': 'v3', 'mood-v4': 'v4'};

// A design's voice window (the bank's mood-art.mjs voiceWindows): when a
// mumble over it may start, in ms. For needs you, the finish and an error,
// 0.12 s after the last attention cue ends; for the rest, 0.45 s in. The
// bank works it out for the new moods' designs, and the older ones follow
// the same rule on their own timelines. sfxgen checks it against the bank.
function voiceMs(id, state, score) {
  const start = protectedSoundStates.includes(state)
    ? Math.max(0, ...score.events.map(e => e.at + effects[e.effect].duration)) + 0.12 : 0.45;
  return Math.round(Number(start.toFixed(6)) * 1000);
}

const designs = catalog.map(a => {
  const file = path.join('svg', a.mood, a.state, `${a.id}.svg`);
  fs.mkdirSync(path.join(out, path.dirname(file)), {recursive: true});
  const scene = makeScene(a.id);
  fs.writeFileSync(path.join(out, file), scene.svg);
  return {
    id: a.id, mood: a.mood, state: a.state, variation: a.variation, name: a.name, seconds: a.seconds,
    ...(a.outcome ? {outcome: a.outcome} : {}), ...(a.startContext ? {ctx: a.startContext} : {}),
    voiceMs: voiceMs(a.id, a.state, scene.score), dialect: dialects[a.renderer], svg: file,
  };
});
fs.writeFileSync(path.join(out, 'designs.json'), JSON.stringify(designs, null, 1) + '\n');
console.log(`bank: ${designs.length} designs into ${out}`);
