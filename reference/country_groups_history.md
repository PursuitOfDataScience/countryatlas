# Dated country-group membership

When each country joined – and where applicable left – each of twelve
international groups. The dated counterpart to
[country_groups_tbl](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_tbl.md),
which is a single current snapshot.

## Usage

``` r
country_groups_history
```

## Format

A tibble with 176 rows:

- group:

  Group name.

- iso3c:

  ISO 3166-1 alpha-3 code.

- country:

  Country name.

- from:

  Date membership took effect.

- to:

  Date membership ended, or `NA` for a current member.

## Details

A snapshot silently misstates any panel that spans an accession: an EU
panel over 2015-2020 either includes the United Kingdom throughout or
excludes it throughout, and both are wrong.
[`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md)
and
[`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md)
read this table when given `as_of`.

## Scope, and what is deliberately absent

Twelve groups are dated: EU, EuroZone, NATO, OECD, ASEAN, EFTA, GCC,
Mercosur, Nordic, Visegrad, BRICS and G7. **Commonwealth, G20 and OPEC
are not**, and that is a decision rather than an omission – their
histories involve suspensions, readmissions and contested dates that
would have to be sourced case by case, and a fabricated date is worse
than an absent one. `country_groups(as_of =)` warns and falls back to
the snapshot for those.

Dates are the treaty or accession date where one exists, otherwise 1
January of the accession year. The table is validated at build time
against
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
#> # A tibble: 10 × 5
#>    group iso3c country        from       to        
#>    <chr> <chr> <chr>          <date>     <date>    
#>  1 EFTA  AUT   Austria        1960-05-03 1995-01-01
#>  2 EFTA  CHE   Switzerland    1960-05-03 NA        
#>  3 EFTA  DNK   Denmark        1960-05-03 1973-01-01
#>  4 EFTA  GBR   United Kingdom 1960-05-03 1973-01-01
#>  5 EFTA  NOR   Norway         1960-05-03 NA        
#>  6 EFTA  PRT   Portugal       1960-05-03 1986-01-01
#>  7 EFTA  SWE   Sweden         1960-05-03 1995-01-01
#>  8 EFTA  FIN   Finland        1961-06-27 1995-01-01
#>  9 EFTA  ISL   Iceland        1970-03-01 NA        
#> 10 EFTA  LIE   Liechtenstein  1991-09-01 NA        
```
