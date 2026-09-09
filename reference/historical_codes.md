# Historical / dissolved entities and their successor states

A curated crosswalk from dissolved entities (Soviet Union, Yugoslavia,
Czechoslovakia, ...) to the modern states that succeeded them – one row
per (entity, successor) pair, dated, so historical panels can be brought
onto the modern ISO spine honestly instead of being silently dropped (or
worse: `countrycode` resolves `"USSR"` to Russia alone). Consumed by
[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
and flagged by
[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md).

## Usage

``` r
historical_codes
```

## Format

A tibble with one row per (entity, successor):

- historical:

  Canonical name of the dissolved entity.

- iso3c_hist:

  The alpha-3 code the entity held at dissolution, where one existed
  (`SUN`, `YUG`, `CSK`, `DDR`, `ANT`, `SCG`, `YMD`, ...); it may since
  have been inherited by a successor (e.g. `YEM`).

- dissolved:

  Year the entity ceased to exist.

- iso3c, country:

  The successor state.

- relation:

  How the successor relates to the entity, per successor: `"succession"`
  if it is a genuinely new state created at `dissolved`, or
  `"continuation"` if the same state carried on (possibly with less
  territory) or a state that already existed absorbed the entity. Sudan
  is both at once – `SDN` continued and `SSD` is new – which is why the
  relation is per successor rather than per entity. The distinction
  matters: a `"continuation"` was *not* created at `dissolved`, so
  testing its data against that year says nothing, and the code did not
  cease to exist either.
  [`audit_time_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_time_coverage.md)
  keys on this column for both reasons.

## Source

Curated from ISO 3166-3 and the historical record.

## Details

Kosovo (`XKX`) is included among the Yugoslavia and
Serbia-and-Montenegro successors on a *territory* basis (its territory
was part of both); filter it out if your analysis follows strict
UN-membership succession.
