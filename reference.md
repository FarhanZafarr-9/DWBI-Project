# Reference — Original Project Intent vs. Phase 2 Results

**Purpose.** This file keeps the *reason* for the project connected to what has
actually been built. Phase 2 is mostly plumbing — schemas, cleaning, loads and
checks — so the "what affects aviation and how does it affect it" story is not
fully visible yet. That story is meant to be told in Phase 3 through the reporting
views, charts and dashboards. This reference records the handover so that nothing
gets lost between the two phases.

Sources: `Phase1/01_Project_Documentation/` (proposal, requirements, business
questions, grain and fact/dimension documents), `PROJECT_CONTEXT.md`,
`SUBMISSION_REPORT.md`, `Phase2/DATA_CLEANING_REPORT.md` and
`Phase2/DATA_QUALITY_REPORT.md`.

---

## 1. What we originally set out to do

The proposal framed the problem like this: delays and cancellations cost airlines
and airports money and customer trust, but the evidence sits in separate systems.
Management cannot easily see **where delays happen, what drives them, or how
reliability relates to passenger demand**.

The objective was one integrated warehouse that lets operations and commercial
managers answer:

- Which airlines, routes, airports and time periods are least reliable?
- What drives delays — carrier, weather, congestion, aircraft, schedule?
- How does reliability relate to passenger demand and load factor?
- Where are the biggest improvement opportunities (high demand, low reliability)?

That is the "what affects aviation and how it affects" question. It has two halves:

| Half | Meaning | Where it lives in the model |
|---|---|---|
| **What affects it** (causes) | Carrier behaviour, weather, air-traffic/NAS, security, late aircraft, airport congestion, aircraft age/model, time of day | Delay-cause measures, `fact_airport_weather`, `fact_aircraft_route`, `dim_time`, `dim_aircraft`, airport flight counts |
| **How it affects** (consequences) | Departure/arrival delay, cancellations and diversions, knock-on effect on passengers and route performance | `fact_flight` delay and status measures, `fact_route_demand` passengers/seats/load factor |

The warehouse was designed so these two halves can be joined through the four
conformed dimensions — **Date, Airport, Airline and Route**. That join is the whole
point of the project; Phase 2 makes it possible, Phase 3 makes it visible.

---

## 2. Requirement coverage

| Requirement | Phase 1 intent | Phase 2 status |
|---|---|---|
| BR1 — delays/on-time by airline, route, airport, time | Core operations view | **Ready.** `fact_flight` carries delay measures plus all four keys. No ranking/slice query built yet. |
| BR2 — five delay causes | Explain *why* flights are late | **Ready.** All five cause-minute columns are loaded. No cause-share analysis yet. |
| BR3 — delays/cancellations vs origin weather | Weather impact | **Partial.** Weather fact is loaded, but UTC-hour grain and NOAA coverage ending 2025-08-27 limit the join; no 2026 weather. |
| BR4 — reliability vs demand/load factor | Commercial impact | **Partial.** Full T-100 demand and load factors are available; the cross-fact join to reliability has not been built. |
| BR5 — aircraft model/age vs delays | Aircraft reliability | **Partial.** `dim_aircraft` is fully loaded (319,418 rows) and the factless route fact exists; no age/model analysis yet. |
| BR6 — date and location drill-down | Hierarchy support | **Ready.** `dim_date` 731 rows, `dim_airport` 2,036 rows with region/city/state hierarchy. |
| BR7 — dashboards | Phase 3 deliverable | **Not started.** `project_reporting` exists but is empty; no Power BI work yet. |

Success criteria from the requirements were: all 10 business questions answerable
from the warehouse alone, documented grain, and working drill-down. Phase 2
satisfies the *data-side* preconditions; the questions themselves still need
reporting objects before they can be called answered.

---

## 3. The 10 business questions — where each one stands

### Group A: Delays and operations (Q1–Q5)

| Q | Original question | What Phase 2 provides | What we can say now | Still needed |
|---|---|---|---|---|
| 1 | Monthly trend in average arrival delay | `fact_flight` × `dim_date`, 469,214 sampled rows across 20 months | Summer 2025 peak (~22 min dep / ~18 min arr in July) and September 2025 trough (8.4 / 2.6 min). M1–M8 2026 runs ~1.2 min above 2025. | Line chart in the DQ report; formal view for Power BI. |
| 2 | Best/worst on-time airlines | `fact_flight` × `dim_airline` (15 rows) | Nothing published yet — the columns are loaded, not ranked. | Simple grouped bar chart + `vw_airline_performance`. |
| 3 | Worst-delayed routes | `fact_flight` × `dim_route` / `dim_airport` | Nothing published yet. | Top-10 delayed-routes bar chart. |
| 4 | Delay-cause share by season | Five cause-minute measures × `dim_date.season` | Not analysed. The measures exist but no cause breakdown has been produced. | Stacked bar / 100% stacked column by season. |
| 5 | Hours and weekdays with most delays | `fact_flight` × `dim_time` / `dim_date` | Not analysed. `dim_time` has 25 rows (hour, band, peak flag). | Heatmap or two bar charts. |

### Group B: Airports and weather (Q6–Q7)

| Q | Original question | What Phase 2 provides | What we can say now | Still needed |
|---|---|---|---|---|
| 6 | Congestion, delays, cancellation rates by airport/state | 2,036 airports, `fact_flight` counts, `dim_flight_status` | Sample shows 8,229 cancelled flights (1.8%), with January 2026 the worst month (1,053). Nothing broken out by airport yet. | Top-airport cancellation-rate bar chart; congestion count by hour. |
| 7 | Visibility/wind/precipitation vs delays | 171,225 full weather fact rows; condition/visibility-band dimension | Weather data is loaded and clean (top stations ~5,720 hourly rows each). **No delay relationship has been tested.** | UTC→local conversion via `dim_airport.time_zone`, then scatter/box plot of delay vs visibility and wind. |

### Group C: Demand (Q8–Q9)

| Q | Original question | What Phase 2 provides | What we can say now | Still needed |
|---|---|---|---|---|
| 8 | Passenger volume and load factor by route/month | Full T-100 fact: 232,281 aggregated rows, 601,435 clean source rows | Already visible: 845.2 M passengers in 2025, 563.7 M in 2026 (partial year). Named routes run 76–87% load factor (LAX–JFK 86.8%, JFK–LAX 85.5%, ORD–LGA 85.6%). | Horizontal bar chart of top routes with load-factor labels. |
| 9 | High demand + low reliability routes | Cross-fact join on Date/Route/Airline | **Not built.** This is the single clearest "how it affects" question and it is still unanswered. | `vw_route_load_reliability` joining `fact_route_demand` to `fact_flight`, then a quadrant scatter (passengers vs delay). |

### Group D: Aircraft (Q10)

| Q | Original question | What Phase 2 provides | What we can say now | Still needed |
|---|---|---|---|---|
| 10 | Aircraft age/model vs delays; distinct aircraft per route | `dim_aircraft` 319,418 rows with manufacturer/model/year built; `fact_aircraft_route` 99,950 sampled rows | Nothing published yet. | Age-band vs delay chart; distinct-aircraft-per-route ranking. |

---

## 4. What Phase 2 already tells us about the original question

Even before dashboards, a few defensible statements can be made from the executed
results:

1. **Reliability has a seasonal shape.** Average departure delay rises to ~18–22
   minutes in June–July and falls to ~8 minutes in September. This is visible in
   the 20-month sample and is the earliest answer to Q1.
2. **2026 is slightly worse than 2025 on a like-for-like basis** — 15.1 vs 13.9
   minutes average departure delay over M1–M8. This respects the source coverage
   rule (never compare full-year 2025 with partial-year 2026).
3. **Cancellation is a real, separately modelled outcome**, not missing data:
   8,229 cancelled flights remain in the fact with a CANCELLED status, while their
   delay measures are deliberately `NULL`. This implements the Phase 1 grain rule
   that cancelled flights stay in `fact_flight` with no delay values.
4. **Demand is concentrated on a small set of high-load routes.** The named top
   routes carry 1.2–1.5 M passengers each at 76–87% load factor, so a reliability
   problem on one of them has an outsized passenger impact. This is the first
   hint of Q9's "biggest improvement opportunities".
5. **The data is trustworthy enough to build on.** 28 DQ checks: 27 pass, 1 warn,
   0 fail; all 19 referential checks returned zero orphans. The one warning is the
   deliberate flight-fact sample, not a defect. The cleaning report documents
   every transformation applied before the facts were loaded.

---

## 5. What Phase 2 deliberately does *not* answer yet

These are known gaps, not oversights. They should be stated plainly in Phase 3
rather than papered over:

- **Reporting layer is empty.** `project_reporting` is declared but has no views or
  marts. No OLAP, no dashboards, so BR7 and the "answer all 10 questions" success
  criterion are still outstanding.
- **Cause analysis is absent.** The five delay-cause columns are loaded but no
  share-by-season or ranking query has been run. Q4 cannot be called answered.
- **Weather relationship is untested.** NOAA ends 2025-08-27 and is UTC while
  flights are local, so any weather-versus-delay claim needs the time-zone
  conversion and a 2025-only comparison window.
- **Aircraft and cross-fact analysis is absent.** Q9 and Q10 need joins that have
  not been written.
- **Sampling.** `fact_flight` is a deterministic 469,214-row sample of 11,730,351
  clean rows (`raw_id % 25 = 0`). It covers all 20 months and preserves the
  monthly shape, but it must be labelled as a sample in every chart caption.
  Route demand, weather, all dimensions and clean staging are full.
- **Unknown members.** 16,448 facts use surrogate key `-1`, and the `UNK-UNK`
  route carries 14.8 M passengers (261 T-100 rows with airport codes missing from
  the 2,036-row seed). This is an INFO-level observation, but it should be
  excluded from named-route rankings and called out in any passenger-total chart.
- **Source coverage.** 2026 On-Time and T-100 end in August; DB1B is only 2025
  Q1–Q2; there is no 2026 NOAA weather. YoY must use M1–M8, and weather YoY is not
  possible. Fare analysis was out of scope from the start.
- **Scope drift from the proposal.** The proposal assumed one calendar year
  (2025) and weather for the 15 busiest airports. Implementation extended flight
  and demand data to 2026-08 to allow like-for-like YoY, and used 30 weather
  stations. Both are sensible upgrades, but the design documents still say
  "one year / 15 airports" — align the wording before submission.

---

## 6. How Phase 3 should close the loop

Keep the visuals tied to the original questions rather than to whatever chart is
easiest. The `instructions.md` note covers PDF presentation; this section is about
*narrative order*:

1. **Start with the effect** — Q1 trend and Q6 cancellation rates. Establishes
   that reliability varies by time and place.
2. **Then show the causes** — Q4 delay causes by season, Q5 hour/weekday pattern,
   Q7 weather relationship, Q10 aircraft age/model. This is the "what affects
   aviation" half.
3. **Then show the consequence** — Q8 load factors and Q9 high-demand/low-
   reliability routes. This is the "how it affects" half and the strongest
   business payoff.
4. **Finish with the opportunity** — the Q9 quadrant view: busy routes that are
   also unreliable are where an operations manager should act first.

A small star-schema figure and an ETL flow diagram near the front of the report
will show *how* the answer was made possible. The DQ scorecard belongs near them
so the reader trusts the numbers that follow.

### 6.1 Handover to the Phase 3 deliverables

Phase 3 is a separate 30% of the course with its own deliverables. The gaps listed
in §5 are not Phase 2 failures — they are the input to Phase 3. Keep the split
clean: do not pull these into Phase 2.

| Phase 3 deliverable | Phase 2 input it builds on | Questions it closes |
|---|---|---|
| Analytical SQL Queries (SQL) | Delay causes in `fact_flight`, `dim_flight_status`, `dim_aircraft`, `dim_time` | Q2, Q3, Q4, Q5, Q10 |
| OLAP Queries (SQL) | Date and airport hierarchies, conformed dimensions | BR6 drill-down; roll-up/slice of Q1–Q8 |
| Reporting Views (SQL) | Empty `project_reporting` schema, `fact_route_demand` + `fact_flight` join | Q8, Q9; BR4 and BR7 |
| Indexing Report (PDF) | 8 indexes on `fact_flight` and 24 monthly partitions already in `03_dw_tables.sql` | Performance evidence for all queries |
| Power BI Dashboard (PBIX) + Dashboard Screenshots (PDF) | All four facts and eight dimensions, cleaned and quality-checked | BR7; Q1–Q10 visually |
| Business Insights Report (PDF) + Final Presentation (PPT) | The early findings in §4 and the narrative order in §6 | The "what affects / how it affects" story end to end |

The star-schema and ETL diagrams suggested for the Phase 2 PDFs are explanatory
figures only. The real dashboards, charts and marts belong to Phase 3.

---

## 7. Ground rules for anyone writing this up

- Use only figures that appear in the markdown reports. The current headline
  numbers are **469,214 sampled flights / 20 months**, **27 pass / 1 warn / 0
  fail**, **232,281 route-demand rows**, **171,225 weather rows**, and **8,229
  cancelled flights with delay measures cleared**.
- Never present the sampled flight fact as a full load, and never compare 2025
  full-year totals with 2026 partial-year totals.
- Label `UNK-UNK` as the Unknown member, not as a real route.
- Where Phase 2 has not answered a question, say so. The honest "built the
  foundation, analysis comes in Phase 3" framing is stronger than a vague claim
  that everything is done.
