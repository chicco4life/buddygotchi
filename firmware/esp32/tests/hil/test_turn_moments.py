"""Event identity, deadline, interruption and bounded typography on real USB."""
import pytest
from test_usb import stick, clean, frame, state, wait_state, clock, press, screenshot

ROWS = [dict(source="codex", working=1, idle=1)]

def moment(stick, id, **changes):
    value = dict(id=id, kind="completed", tier="caption", expression="pleased",
                 text="Layout turn finished.", count=1, age=0, left=4000)
    value.update(changes)
    frame(stick, state="working", agents=ROWS, moment=value)
    return value

@pytest.mark.parametrize("tier,left,layer", [("face",1200,"face"),("caption",4000,"face"),("full",5000,"moment")])
def test_tiers_expire_at_host_deadline(stick,tier,left,layer):
    base=state(stick)["now"];clock(stick,base)
    moment(stick,7000+left,tier=tier,left=left,text="" if tier=="face" else "Layout turn finished.")
    clock(stick,base+300)
    wait_state(stick,momentVisible=True,momentTier=tier,layer=layer)
    clock(stick,base+left)
    wait_state(stick,momentVisible=False,layer="face")

def test_keepalive_clear_resend_and_new_event_with_same_text(stick):
    base=state(stick)["now"];clock(stick,base)
    m=moment(stick,8001)
    clock(stick,base+3500)
    frame(stick,state="working",agents=ROWS,moment=m) # stale left must not extend
    clock(stick,base+4000)
    wait_state(stick,momentVisible=False)
    frame(stick,state="working",agents=ROWS)
    frame(stick,state="working",agents=ROWS,moment=m)
    wait_state(stick,momentVisible=False)
    moment(stick,8002)
    clock(stick,base+4300)
    wait_state(stick,momentVisible=True)

@pytest.mark.parametrize("interruption", ["request","details","sleep"])
def test_interrupted_moment_never_replays(stick,interruption):
    id={"request":8101,"details":8102,"sleep":8103}[interruption]
    m=moment(stick,id)
    wait_state(stick,momentVisible=True)
    extra=dict(threads=[[0,1,"Layout"]],threadTotal=1)
    if interruption=="request":
        frame(stick,state="needsYou",moment=m,card=dict(id="req",tool="Question",gloss="Input",n=1,of=1))
    elif interruption=="details":
        frame(stick,state="working",agents=ROWS,moment=m,**extra);press(stick)
    else: frame(stick,state="asleep",moment=m)
    wait_state(stick,momentVisible=False)
    if interruption=="details": press(stick)
    frame(stick,state="working",agents=ROWS,moment=m)
    wait_state(stick,momentVisible=False)

def test_hint_remains_fixed_during_caption_fade(stick):
    base=state(stick)["now"];clock(stick,base)
    moment(stick,8201)
    bands=[]
    for age in (125,600,3800,4000):
        clock(stick,base+age)
        raw=screenshot(stick)
        # Wash changes underneath; compare bright hint pixels only.
        pixels=[int.from_bytes(raw[i:i+2],"little") for i in range((280-35)*456*2,len(raw),2)]
        bands.append([v for v in pixels if v>0x8000])
    assert bands[0]
    assert all(band==bands[0] for band in bands[1:])

@pytest.mark.parametrize("change", [dict(tier="huge"),dict(expression="angry"),dict(text="x"*49),dict(kind="start",text="x"*25),dict(left=8001),dict(age=7000,left=2000),dict(text="한글"),dict(id=0)])
def test_invalid_moment_rejects_whole_frame(stick,change):
    moment(stick,8301)
    before=state(stick)
    moment(stick,8302,**change) if "id" not in change else moment(stick,change["id"])
    after=state(stick)
    assert after["badFrames"]==before["badFrames"]+1
    assert after["momentId"]==8301

def test_long_word_is_silent_instead_of_clipped(stick):
    base=state(stick)["now"];clock(stick,base)
    moment(stick,8401,text="W"*48)
    clock(stick,base+600)
    a=screenshot(stick)
    moment(stick,8401,text="",age=600,left=3400)
    b=screenshot(stick)
    assert a==b
