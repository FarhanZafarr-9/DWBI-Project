# Source Verification Report - Null Pointers (DL3004)

**Method:** each source was checked two ways. *Downloaded* = pulled and inspected in the sandbox. *Docs only* = the sandbox cannot reach the host (BTS, NOAA, FAA were blocked), so the source was verified from official documentation and search results, not by downloading real files.

| Source | Status | Result |
|---|---|---|
| OurAirports | Downloaded | 2,036 US airports with an IATA code. All 30 top airports found, each with an ICAO code. |
| OpenFlights | Downloaded | Time zones for 1,123 of those airports. The other 913 were filled from coordinates (timezonefinder). |
| US holidays | Generated | 11 federal holidays in 2025 (observed dates included), added to `dim_date_2025.csv` (365 rows). |
| BTS On-Time | Docs only | 2025 data is published. Raw monthly files are authoritative. Tail and flight number are only in the download form/bulk files. |
| BTS T-100 Domestic Segment | Docs only | Passengers, seats, departures per carrier-route-month. No bulk URL, needs the TranStats form (see README). |
| BTS DB1B Market | Docs only | Confirmed as a 10% ticket sample with market fare and passengers. |
| NOAA Global Hourly (ISD) | Docs only | Station-year CSVs exist. Being superseded by GHCNh but still downloadable. |
| FAA Registry | Docs only | Nightly `ReleasableAircraft.zip` with MASTER, ACFTREF, DEREG. |

## Confirmed (matches our design)
- DB1B is a 10% ticket sample, so fares are estimates.
- Weather is UTC while BTS flight times are local, so the time-zone step in ETL is needed.
- Weather values arrive as packed strings (VIS, WND, TMP), so they need parsing in staging.

## Differences found (design impact)
1. **Airlines:** BTS On-Time only includes carriers above 0.5% of domestic revenue (14 carriers for 2025), so Dim_Airline is small (~14 rows).
2. **DB1B markets are not flight legs:** a market is an origin-destination pair after trip breaks, so it can include connecting itineraries. Keep only `MktCoupons = 1` (non-stop) so Fact_Fare joins cleanly to Dim_Route.
3. **T-100 includes cargo and charter:** filter `CLASS = F` (scheduled passenger) before loading Fact_Route_Demand.
4. **FAA is one current snapshot:** aircraft deregistered since 2025 are only in DEREG.txt, and there is no registration history in a single snapshot.
5. **Tail number join:** BTS uses `N12345`, FAA MASTER uses `12345` (no N). Add the prefix before joining.
6. **Time zone and region are derived:** no source provides them. Time zone comes from OpenFlights/coordinates, region from state using Census regions.
7. **Weather airports:** the top-30 list is assumed (static list of busy airports). Confirm it against BTS flight counts after loading.
8. **Weather is not strictly hourly:** observations are irregular, so round to the hour in ETL.

## Not confirmed
- 2025 availability of T-100 and DB1B (BTS On-Time 2025 is confirmed). If either is missing, fall back to 2024 for all sources.
- Exact download URL patterns for BTS and NOAA: they follow documented conventions but could not be tested here.
- The scripts in `scripts/` compile and the reference build runs, but the download and verify steps have not been run against real files.
