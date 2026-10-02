# Dated country-group membership

When each country joined – and where applicable left, or was suspended
from – each of nineteen international groups. The dated counterpart to
[country_groups_tbl](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_tbl.md),
which is a single current snapshot.

## Usage

``` r
country_groups_history
```

## Format

A tibble with 288 rows:

- group:

  Group name.

- iso3c:

  ISO 3166-1 alpha-3 code.

- country:

  Country name.

- from:

  Date the spell took effect.

- to:

  The first date on which it no longer held (it runs up to the day
  before), or `NA` for one still in force. The United Kingdom's EU `to`
  is therefore 2020-02-01: it left at the end of 31 January 2020.

- status:

  `"member"` or `"suspended"`. A country can have several spells in a
  group: Seychelles left SADC in 2004 and rejoined in 2008, and Syria
  was suspended from the Arab League from 2011 to 2023.
  [`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md)
  and
  [`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md)
  count the member spells only.

## Details

A snapshot silently misstates any panel that spans an accession: an EU
panel over 2015-2020 either includes the United Kingdom throughout or
excludes it throughout, and both are wrong.
[`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md)
and
[`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md)
read this table when given `as_of`.

## Scope, and what is deliberately absent

Nineteen groups are dated: EU, EuroZone, NATO, OECD, ASEAN, EFTA, GCC,
Mercosur, Nordic, Visegrad, BRICS, G7, and since 4.0.0 SCO, CPTPP, RCEP,
EAC, SADC, APEC (member economies, so Hong Kong and Taiwan too) and the
Arab League (`"ArabLeague"`). Every date carries its source in
`data-raw/country_groups_history.R`. **Commonwealth, G20 and OPEC are
not**, and that is a decision rather than an omission: the
Commonwealth's and OPEC's suspensions, lapses and readmissions are dated
unevenly by the sources, and G20's members include the EU and the
African Union, which are not countries. A fabricated date is worse than
an absent one, so `country_groups(as_of =)` warns and falls back to the
snapshot for those. RCEP leaves out Myanmar, whose ratification the
ASEAN Secretariat questioned and whose date of entry into force is
disputed.

Dates are the treaty, accession or decision date where one exists; where
the sources give only the month, the 1st of that month (APEC's
accessions). The table is validated at build time against
[country_groups_tbl](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_tbl.md):
the members current today must reproduce the snapshot exactly, for every
group covered.

## See also

[`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md),
[`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md),
[`country_timeline()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_timeline.md)

## Examples

``` r
# EFTA is the instructive one: most of its founders left, for the EU
subset(country_groups_history, group == "EFTA")
#> # A tibble: 10 × 6
#>    group iso3c country        from       to         status
#>    <chr> <chr> <chr>          <date>     <date>     <chr> 
#>  1 EFTA  AUT   Austria        1960-05-03 1995-01-01 member
#>  2 EFTA  CHE   Switzerland    1960-05-03 NA         member
#>  3 EFTA  DNK   Denmark        1960-05-03 1973-01-01 member
#>  4 EFTA  GBR   United Kingdom 1960-05-03 1973-01-01 member
#>  5 EFTA  NOR   Norway         1960-05-03 NA         member
#>  6 EFTA  PRT   Portugal       1960-05-03 1986-01-01 member
#>  7 EFTA  SWE   Sweden         1960-05-03 1995-01-01 member
#>  8 EFTA  FIN   Finland        1961-06-27 1995-01-01 member
#>  9 EFTA  ISL   Iceland        1970-03-01 NA         member
#> 10 EFTA  LIE   Liechtenstein  1991-09-01 NA         member
```
