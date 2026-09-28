// Exports the animation bank's designs for facegen.py, which runs this:
// every design's SVG, made by the bank's own generator
// (internal/boop-design/boop-sound-bank-v4/runtime/), into DIR/svg/, and
// its catalogue entry into DIR/designs.json. DIR is ignored by git; the
// bank is the designs' only source (plan/DEVICE.md §6).
//
//     node internal/tools/facegen/bank.mjs --out DIR
import fs from 'node:fs';
import path from 'node:path';

import {catalog} from '../../boop-design/boop-sound-bank-v4/runtime/catalog.mjs';
import {makeScene} from '../../boop-design/boop-sound-bank-v4/runtime/bank.mjs';

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
const designs = catalog.map(a => {
  const file = path.join('svg', a.mood, a.state, `${a.id}.svg`);
  fs.mkdirSync(path.join(out, path.dirname(file)), {recursive: true});
  fs.writeFileSync(path.join(out, file), makeScene(a.id).svg);
  return {
    id: a.id, mood: a.mood, state: a.state, variation: a.variation, name: a.name, seconds: a.seconds,
    ...(a.outcome ? {outcome: a.outcome} : {}), ...(a.startContext ? {ctx: a.startContext} : {}),
    dialect: dialects[a.renderer], svg: file,
  };
});
fs.writeFileSync(path.join(out, 'designs.json'), JSON.stringify(designs, null, 1) + '\n');
console.log(`bank: ${designs.length} designs into ${out}`);
