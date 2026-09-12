import base64,json,re,sys,time,zlib,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'firmware/esp32/tools'))
import buddyctl,shots
from shot_cells import cells,prepare
from golden import read_png
OUT=ROOT/'plan/evidence/working-sleep-2026-09-12';OUT.mkdir(parents=True,exist_ok=True)
observations={}
with buddyctl.SerialBuddy(timeout=5) as s:
 def shot(name):
  time.sleep(.15) # let the next loop apply brightness after a frozen-clock change
  s.write_line('screenshot');buf,p=s.read_until(buddyctl.parse_screenshot,20)
  header,start,end,footer=p
  raw=base64.b64decode(re.sub(rb'\s+',b'',buf[start:end]),validate=True)
  assert len(raw)==int(footer.group(1)) and zlib.crc32(raw)&0xffffffff==int(footer.group(2),16)
  w,h=int(header.group(1)),int(header.group(2))
  buddyctl.write_png(OUT/f'{name}.png',w,h,buddyctl.rgb565le_to_rgb888(raw,w,h))
  observations[name]=s.framed_json('state','STATE',3)
  (OUT/'states.json').write_text(json.dumps(observations,indent=2))
 prepare(s)
 s.write_line('{"v":2,"state":"asleep","cosmetic":{}}');time.sleep(2)
 base=s.framed_json('state','STATE',3)['now']
 s.framed_json(f'clock {base}','CLOCK',3);shot('sleep-rest')
 s.write_line('tap 228 140');s.read_until(lambda b:b'<<TAP ok>>' in b,3)
 s.framed_json(f'clock {base+300}','CLOCK',3);shot('sleep-peek')
 s.framed_json(f'clock {base+1500}','CLOCK',3);shot('sleep-after')
 assert observations['sleep-rest']['brightness']==72
 assert observations['sleep-peek']['brightness']==210
 assert observations['sleep-after']['brightness']==72
 s.write_line('clock clear');s.write_line('imu clear')
(OUT/'states.json').write_text(json.dumps(observations,indent=2))
# All working fixtures plus sleep; independent repeat guards deterministic ink/pose.
selected={n:c for n,c in cells().items() if c['state'] in ('working','asleep') and not c.get('trigger') and not c.get('notice')}
shots.cells=lambda:selected
for index in (1,2):
 shots.OUT=Path(f'/tmp/boop-visibility-goldens-{index}')
 assert shots.main()==0
for name in selected:
 a=Path('/tmp/boop-visibility-goldens-1')/(name+'.png')
 b=Path('/tmp/boop-visibility-goldens-2')/(name+'.png')
 assert read_png(a)==read_png(b),name
 shutil.copyfile(b,ROOT/'firmware/esp32/tests/golden/ws-amoled164'/b.name)
shutil.copyfile('/tmp/boop-visibility-goldens-2/contact-sheet.png',OUT/'contact-sheet.png')
print(f'{len(selected)} working/sleep goldens reproduced twice with identical pixels.',flush=True)
