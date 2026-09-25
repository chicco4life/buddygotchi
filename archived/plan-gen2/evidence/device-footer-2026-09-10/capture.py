import argparse, base64, json, re, sys, time, zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'firmware/esp32/tools'))
import buddyctl
from shot_cells import prepare
OUT=ROOT/'plan/evidence/device-footer-2026-09-10'
OUT.mkdir(parents=True,exist_ok=True)
import shots
from shot_cells import cells
frames={k:v for k,v in cells().items() if k in ('card-fine','card-checkIt','card-careful')}
for name,gloss,tool,count in (
 ('queued','Runs a command','Bash',3),
 ('long-description','Checks packages and generates a detailed verification report','Bash',1),
 ('korean-description','프로젝트 파일을 확인하고 결과를 정리합니다','Bash',1),
 ('long-tool','Runs a command','LongToolNameForTheCheck',3)):
 assert len(tool.encode())<=23 and len(gloss.encode())<=63
 frames[name]={'v':2,'state':'needsYou','dots':2,'settle':2500,'card':{'id':name,'tool':tool,'gloss':gloss,'stakes':'checkIt','n':1,'of':count,'approval':True}}
shots.cells=lambda:frames
shots.OUT=OUT
assert shots.main()==0

with buddyctl.SerialBuddy(timeout=5) as s:
 def shot(name):
  s.write_line('screenshot')
  buf,p=s.read_until(buddyctl.parse_screenshot,20)
  header,start,end,footer=p
  raw=base64.b64decode(re.sub(rb'\s+',b'',buf[start:end]),validate=True)
  assert len(raw)==int(footer.group(1)) and zlib.crc32(raw)&0xffffffff==int(footer.group(2),16)
  w,h=int(header.group(1)),int(header.group(2))
  buddyctl.write_png(OUT/f'{name}.png',w,h,buddyctl.rgb565le_to_rgb888(raw,w,h))
 def scene(name,stakes='fine',gloss='Runs a command',tool='Bash',count=1):
  assert len(tool.encode())<=23 and len(gloss.encode())<=63
  prepare(s)
  s.write_line(json.dumps({'v':2,'state':'needsYou','dots':2,'card':{'id':name,'tool':tool,'gloss':gloss,'stakes':stakes,'n':1,'of':count,'approval':True}},ensure_ascii=False))
  time.sleep(2.6)
  got=s.framed_json('state','STATE',3)
  assert got['cardId']==name and got['layer']=='card',got
  s.framed_json('clock freeze','CLOCK',3)
  shot(name)
  return s.framed_json('state','STATE',3)
 try:
  scene('hold-start')
  s.framed_json('clock clear','CLOCK',3)
  s.write_line('press a 900')
  time.sleep(.45)
  shot('hold-progress')
  time.sleep(.65)
  shot('hold-released')
  scene('feedback-start')
  s.framed_json('clock clear','CLOCK',3)
  s.write_line('press a 100');time.sleep(.2)
  shot('sending')
  s.write_line('{"v":2,"state":"idle"}');time.sleep(.15)
  shot('confirmed')
 finally:
  s.write_line('clock clear');s.write_line('imu clear')
print('Captured footer review images:',OUT)
