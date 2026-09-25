# Latency scenario, 2026-09-09 08:02 local, fw dev+f7b1937911ff, 5 rounds

Host-clock upper bounds (USB state poll adds up to one serial round trip).

| Path | p50 | p90 | max | budget | within |
| --- | --- | --- | --- | --- | --- |
| hook -> card | 282 ms | 398 ms | 398 ms | 500 ms | yes |
| button -> decision | 131 ms | 137 ms | 137 ms | 300 ms | yes |
| state -> frame | 62 ms | 124 ms | 124 ms | 250 ms | yes |

## Before (same day, with-response BLE writes, default connection interval)

| Path | p50 | p90 | max | budget | within |
| --- | --- | --- | --- | --- | --- |
| hook -> card | 406 ms | 683 ms | 683 ms | 500 ms | NO |
| button -> decision | 123 ms | 147 ms | 147 ms | 300 ms | yes |
| state -> frame | 118 ms | 173 ms | 173 ms | 250 ms | yes |

Hook-to-card was dominated by the with-response chunk writes; without-response writes brought p90 from 683 ms to 398 ms. The firmware's 15-30 ms connection-interval request alone changed nothing measurable.
