"""Host-only source guard: presentation code must use the virtual clock."""
from collections import Counter
from pathlib import Path
import re

# Exact real-clock call sites: physical holds, uptime, injected releases,
# and the slow hardware battery poll. No real randomness is allowed.
REAL_CLOCK_SITES = {
    "main.cpp": Counter({
        "uint32_t real = millis(), now = nowMs();": 1,  # buttonsTick: physical holds
        'd["up"]=millis(); d["heap"]=ESP.getFreeHeap(); d["heapMin"]=ESP.getMinFreeHeap(); d["heapBig"]=ESP.getMaxAllocHeap();': 1,  # telemetry: uptime
        "buttons[i].injected=true; buttons[i].injectedUntil=millis()+duration;": 1,  # handleSerialCommand: real release
        "if (millis()-batteryAt>=2000) {": 1,  # loop: battery poll interval
        "batteryAt=millis(); int b=halBatteryPct(); bool c=halIsCharging();": 1,  # loop: battery poll timestamp
    }),
    "face.h": Counter(),
    "presence.h": Counter(),
}


def test_animation_clock():
    root = Path(__file__).resolve().parents[2] / "firmware"
    for name, allowed in REAL_CLOCK_SITES.items():
        # Scan each entire file, including helpers and newly added functions.
        source = (root / name).read_text()
        actual = Counter(
            source[source.rfind("\n", 0, call.start())+1:source.find("\n", call.end())].strip()
            for call in re.finditer(r"\b(?:millis|random)\s*\(", source)
        )
        assert actual == allowed, f"{name}: unexpected {actual - allowed}; missing {allowed - actual}"
