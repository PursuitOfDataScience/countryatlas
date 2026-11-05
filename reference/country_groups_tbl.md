# Country-group membership (point-in-time)

A curated, dated membership table for the common country groups.

## Usage

``` r
country_groups_tbl
```

## Format

A tibble with columns `group`, `iso3c`, `country`.

## Source

Curated from official membership lists, as of the date above. (This used
to point at the package `NEWS` for the reference date, where two
different dates were on record – an Rd should not delegate a fact to a
changelog.)

## The groups

Twenty-six groups: `"EU"`, `"EuroZone"`, `"NATO"`, `"OECD"`, `"G7"`,
`"G20"`, `"BRICS"`, `"ASEAN"`, `"EFTA"`, `"Commonwealth"`, `"OPEC"`,
`"Mercosur"`, `"GCC"`, `"Nordic"`, `"Visegrad"`, `"SCO"`, `"CPTPP"`,
`"RCEP"`, `"EAC"`, `"SADC"`, `"APEC"`, `"ArabLeague"`, and since 4.0.0
the African Union (`"AU"`), `"ECOWAS"`, `"CARICOM"` (full members) and
the Pacific Islands Forum (`"PIF"`). Only countries and territories with
an ISO 3166-1 code are listed: the G20's European Union and African
Union members are not, and neither is the African Union's Sahrawi Arab
Democratic Republic, which has no code of its own. A suspended member is
a member here;
[country_groups_history](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_history.md)
records the suspensions it can date.

## As of when

Membership is a snapshot taken on **2026-11-01**, carried on the table
itself:

    attr(country_groups_tbl, "as_of")
    #> [1] "2026-11-01"

Read the attribute rather than this paragraph if you need the date in
code; it is set from a single constant in `data-raw/build_datasets.R`,
so it cannot drift from the data the way a hand-written date can. For
membership at any other date use
[country_groups_history](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_history.md)
and [country_groups(as_of =
)](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md),
which is the table this snapshot is a slice of.
