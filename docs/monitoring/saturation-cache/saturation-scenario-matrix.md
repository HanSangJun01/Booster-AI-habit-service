# Saturation Scenario Matrix — B-axis Redis Necessity Test

> Goal: drive load until a resource saturates, and identify **which resource saturates first**
> (HikariCP connection pool / DB CPU on GROUP BY row-scan / app CPU), so we can decide whether
> Redis caching is justified — and for **which** endpoint it actually helps.
>
> **think-time = 0** in every scenario (pure saturation; not a realistic-traffic model).
> Seeded by `monitoring/scripts/b-axis-seed-saturation.sql` (idempotent, `SAT_` prefix).

## Seeded data & target identifiers (verified)

| Surface | challenge_id(s) | duration | participants | check-ins | notes |
|---|---|---|---|---|---|
| HOT-KEY | **145** (SAT_HOT_1), **146** (SAT_HOT_2) | 120d | 10 each | **1200 each** | deep per-user history — the Redis-candidate target |
| BREADTH | **147 – 644** (498 challenges) | 20d | 10 each | ~200 each | reads fan out across many challenge_id |
| Totals (SAT) | 500 challenges | — | 5000 | **102,000** | avg 20.4 check-ins/participant |

- Valid `X-User-Id` for HOT-KEY team-detail: **1000001** (any of 1000001–1000010; every SAT challenge reuses this user_id pool).
- All participants are `CONFIRMED`; each challenge has teams `A팀`/`B팀` (5 members each).
- Check-in status mix: SUCCESS 71400 / FAILED 10200 / PENDING 10200 / LATE_SUCCESS 10200.
- Leaderboard counts only `SUCCESS` (`countByChallengeIdAndStatusGroupByParticipant`), so HOT personal `checkInCount` ≈ 84/participant over the 120-day scan.

## Endpoint cost model (from source — grounds the hypotheses)

| Endpoint | DB work per request | Connection hold | Row-scan surface |
|---|---|---|---|
| `GET /api/challenges/{id}/leaderboards?type=PERSONAL` | 2 queries: participants-by-status (~10 rows) **+ GROUP BY over challenge_check_ins WHERE challenge_id=? AND status='SUCCESS'** | whole request under `@Transactional(readOnly=true)` → **1 pooled conn held per in-flight request** | **HOT: ~1200 rows; BREADTH: ~200 rows** ← scales with history depth |
| `GET /api/challenges/{id}/leaderboards?type=TEAM` | 1 query: teams-by-challenge (2 rows) + in-memory sort | 1 conn, very short | ~2 rows (near-zero) — **control** for isolating pool vs scan cost |
| `GET /api/challenges/{id}/team-detail` (`X-User-Id`) | team comparison: member lists + today's check-ins | 1 conn | moderate (per-team member + date-filtered check-ins) |
| `GET /api/challenges/{id}` | single challenge fetch | 1 conn, short | 1 row — baseline |
| `GET /api/challenges` (list) | paged challenge list | 1 conn | page-bounded |

HikariCP default pool = 10 connections. Because PERSONAL holds its connection for the full
2-query readOnly transaction, concurrent in-flight PERSONAL requests > pool size ⇒ requests queue
on `connectionTimeout` ⇒ **HikariCP `pending` is the earliest saturation signal to watch.**

## Scenario matrix

| # | Name | Endpoint | Load type | Ramp (VU stages, 0 think-time) | Primary observed hypothesis |
|---|---|---|---|---|---|
| S1 | HOT PERSONAL | `/145/leaderboards?type=PERSONAL` | HOT-KEY: single id hammered | 50→100→200→400→800 | **HikariCP `pending` spikes first**; then p95 latency climbs as GROUP-BY-1200 queues behind 10 conns. **Prime Redis candidate.** |
| S2 | HOT TEAM (control) | `/145/leaderboards?type=TEAM` | HOT-KEY: single id | 50→100→200→400→800 | Near-zero DB rows. If it saturates ~same VU as S1 ⇒ bottleneck is **pool/connection-acquire, not row-scan** (weakens Redis case). If it holds far longer ⇒ S1 pain is **query cost** (strengthens Redis case). |
| S3 | HOT team-detail | `/145/team-detail` (`X-User-Id:1000001`) | HOT-KEY: single id | 50→100→200→400 | Heavier per-request query + conn hold ⇒ saturates **earlier** than S1; watch pool `pending` + DB CPU together. |
| S4 | BREADTH PERSONAL | `/{147..644}/leaderboards?type=PERSONAL` | BREADTH: id randomized per request across 498 | 50→100→200→400→800 | Same total QPS as S1 but spread over 498 ids ⇒ **larger buffer working-set, more index-range touches**, lower per-query rows. A per-challenge Redis cache would have **low hit-rate here** → demonstrates Redis is not a breadth fix. |
| S5 | HOT vs BREADTH depth | S1 vs S4 side-by-side at matched VU | compare | fixed 200 VU | Isolates **DEEP-HISTORY effect**: HOT GROUP BY scans ~6× rows (1200 vs 200). Latency delta = row-scan contribution vs connection contribution. |
| S6 | Mixed realistic | 70% S4 + 20% S1 + 10% S3 | mixed | 100→300→600 | Which resource caps aggregate throughput under blended traffic; where the knee is. |

### Metrics to capture each stage
- HikariCP: `active`, `idle`, **`pending`**, `connectionTimeout` errors (earliest signal).
- DB: `pg_stat_activity` active/waiting, per-query mean time (`pg_stat_statements`), CPU.
- App: JVM CPU, GC, tomcat busy threads.
- Client: RPS, p50/p95/p99, error rate, first-error VU level.

### Decision rule (Redis go/no-go)
- **Redis JUSTIFIED** if: S1 saturates on **query cost** (S2 control holds much longer) AND HOT ids
  concentrate traffic (high cache hit-rate) → cache the PERSONAL leaderboard result per challenge.
- **Redis WEAK / NO** if: S1 and S2 saturate together (bottleneck = pool/conn, fix with pool sizing),
  OR the real traffic shape is S4-like (breadth, low hit-rate) where a per-challenge cache rarely hits.

## Handoff
- worker-2 (load): hammer **S1 first** (`/145/leaderboards?type=PERSONAL`), then run S2 as the control,
  then S4 breadth across ids 147–644. Use the verified URLs below. No think-time.
- worker-3 (bottleneck): watch **HikariCP `pending`** as the leading indicator on S1; correlate with
  DB GROUP-BY mean time and compare S1↔S2↔S4 to attribute saturation to pool vs row-scan vs breadth.

### Verified curl examples (all returned 200)
```
curl "http://localhost:8080/api/challenges/145/leaderboards?type=PERSONAL"
curl "http://localhost:8080/api/challenges/145/leaderboards?type=TEAM"
curl -H "X-User-Id: 1000001" "http://localhost:8080/api/challenges/145/team-detail"
curl "http://localhost:8080/api/challenges/145"
curl "http://localhost:8080/api/challenges/145/teams"
curl "http://localhost:8080/api/challenges/500/leaderboards?type=PERSONAL"   # breadth sample
```
