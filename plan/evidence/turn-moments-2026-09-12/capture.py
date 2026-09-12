import base64,json,re,sys,time,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'firmware/esp32/tools'))
import buddyctl
OUT=ROOT/'plan/evidence/turn-moments-2026-09-12'
OUT.mkdir(parents=True,exist_ok=True)
observations={}
with buddyctl.SerialBuddy(timeout=5) as s:
 def shot(name):
  s.write_line('screenshot');buf,p=s.read_until(buddyctl.parse_screenshot,20)
  header,start,end,footer=p
  raw=base64.b64decode(re.sub(rb'\s+',b'',buf[start:end]),validate=True)
  assert len(raw)==int(footer.group(1)) and zlib.crc32(raw)&0xffffffff==int(footer.group(2),16)
  w,h=int(header.group(1)),int(header.group(2))
  buddyctl.write_png(OUT/f'{name}.png',w,h,buddyctl.rgb565le_to_rgb888(raw,w,h))
 try:
  s.write_line('clock clear');s.write_line('imu set 0 0 1')
  s.write_line('{"v":2,"state":"working","cosmetic":{}}');time.sleep(2)
  from shot_cells import cells
  for name, cell in cells().items():
   if not name.startswith('moment-'): continue
   base=s.framed_json('state','STATE',3)['now']+10
   s.framed_json(f'clock {base}','CLOCK',3)
   cell=dict(cell);cell.pop('settle');cell.pop('t',None)
   cell['moment']['id']+=1000
   s.write_line(json.dumps(cell));time.sleep(.15)
   left=cell['moment']['left']
   offsets=[('arriving',125),('visible',600),('departing',left-200),('expired',left)]
   if name=='moment-full': offsets=[('arriving',125),('pulling',350),('visible',600),('releasing',900),('settled',1300),('departing',4800),('expired',5000)]
   for suffix,age in offsets:
    s.framed_json(f'clock {base+age}','CLOCK',3);shot(name+'-'+suffix)
    observations[name+'-'+suffix]=s.framed_json('state','STATE',3)

 finally:
  s.write_line('clock clear');s.write_line('imu clear')
(OUT/'states.json').write_text(json.dumps(observations,indent=2))
print('Captured moment lifecycle screenshots',OUT)

# Independently capture each affected existing golden twice before recording.
import shots, shutil
from shot_cells import cells
names=['glance-working','glance-last']+[f'scope-{kind}-{lang}' for lang in ('en','ko') for kind in ('face','idle','dashboard')]
names += [name for name in cells() if name.startswith('moment-')]
selected={name:cells()[name] for name in names}
shots.cells=lambda:selected
for index in (1,2):
 shots.OUT=Path(f'/tmp/boop-moments-goldens-{index}')
 assert shots.main()==0
from golden import read_png
for name in names:
 a=Path('/tmp/boop-moments-goldens-1')/(name+'.png')
 b=Path('/tmp/boop-moments-goldens-2')/(name+'.png')
 assert read_png(a)==read_png(b),name
 shutil.copyfile(b,ROOT/'firmware/esp32/tests/golden/ws-amoled164'/b.name)
print('Fourteen affected/new goldens reproduced twice with identical pixels and recorded.')
