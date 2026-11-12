"""Rebuilds data/reference seeds: dim_airport_seed.csv, dim_date_2025.csv, weather_airports_top30.csv.
Inputs (downloaded from GitHub): OurAirports airports.csv, OpenFlights airports.dat."""
import pathlib, pandas as pd, holidays
from timezonefinder import TimezoneFinder
REF = pathlib.Path(__file__).resolve().parents[1] / "data" / "reference"
YEAR = 2025
TOP30 = "ATL DFW DEN ORD LAX JFK CLT LAS MCO MIA PHX SEA SFO EWR IAH BOS FLL MSP LGA DTW PHL SLC DCA SAN BWI TPA AUS IAD BNA MDW".split()
CENSUS = {"Northeast": "CT ME MA NH RI VT NJ NY PA", "Midwest": "IL IN MI OH WI IA KS MN MO NE ND SD",
          "South": "DE DC FL GA MD NC SC VA WV AL KY MS TN AR LA OK TX", "West": "AZ CO ID MT NV NM UT WY AK CA HI OR WA"}
region = {s: r for r, v in CENSUS.items() for s in v.split()}

a = pd.read_csv(REF / "ourairports_airports.csv")
us = a[(a.iso_country == "US") & a.iata_code.notna()].copy()
of = pd.read_csv(REF / "openflights_airports.dat", header=None, na_values=["\\N"],
                 names=["id","name","city","country","iata","icao","lat","lon","alt","tz_offset","dst","tz","type","source"])
us = us.merge(of[of.iata.notna()][["iata", "tz"]].drop_duplicates("iata"), left_on="iata_code", right_on="iata", how="left")
tf = TimezoneFinder(); m = us.tz.isna()
us.loc[m, "tz"] = [tf.timezone_at(lat=r.latitude_deg, lng=r.longitude_deg) for r in us[m].itertuples()]
us["state"] = us.iso_region.str[3:]; us["region"] = us.state.map(region)
us.rename(columns={"name": "airport_name", "municipality": "city", "latitude_deg": "latitude", "longitude_deg": "longitude",
                   "type": "airport_type", "tz": "time_zone"})[
    ["iata_code","icao_code","airport_name","city","state","region","latitude","longitude","elevation_ft","airport_type","time_zone"]
].to_csv(REF / "dim_airport_seed.csv", index=False)
pd.DataFrame({"iata_code": TOP30, "icao_code": ["K" + c for c in TOP30]}).to_csv(REF / "weather_airports_top30.csv", index=False)

h = holidays.US(years=YEAR, observed=True)
d = pd.DataFrame({"full_date": pd.date_range(f"{YEAR}-01-01", f"{YEAR}-12-31")})
d["date_key"] = d.full_date.dt.strftime("%Y%m%d").astype(int); d["day_of_week"] = d.full_date.dt.day_name()
d["week_of_year"] = d.full_date.dt.isocalendar().week.astype(int); d["month"] = d.full_date.dt.month
d["month_name"] = d.full_date.dt.month_name(); d["quarter"] = d.full_date.dt.quarter; d["year"] = YEAR
d["is_weekend"] = d.full_date.dt.dayofweek >= 5; d["holiday_name"] = d.full_date.dt.date.map(lambda x: h.get(x))
d["is_holiday"] = d.holiday_name.notna()
d["season"] = d.month.map(lambda m: "Winter" if m in (12,1,2) else "Spring" if m in (3,4,5) else "Summer" if m in (6,7,8) else "Fall")
d.to_csv(REF / "dim_date_2025.csv", index=False)
print("reference seeds rebuilt")
