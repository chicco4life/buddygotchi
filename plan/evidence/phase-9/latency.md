# Latency scenario, 2026-09-09 07:46 local, fw dev+7b5d1703a342, 5 rounds

Host-clock upper bounds (USB state poll adds up to one serial round trip).

| Path | p50 | p90 | max | budget | within |
| --- | --- | --- | --- | --- | --- |
| hook -> card | 406 ms | 683 ms | 683 ms | 500 ms | NO |
| button -> decision | 123 ms | 147 ms | 147 ms | 300 ms | yes |
| state -> frame | 118 ms | 173 ms | 173 ms | 250 ms | yes |
