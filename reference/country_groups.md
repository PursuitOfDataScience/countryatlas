# Country-group membership

Answers the constant question "is this country in the EU / OECD / G7 /
G20 / BRICS / ...?" from a curated membership table. By default that is
the current snapshot
([country_groups_tbl](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_tbl.md));
pass `as_of` to ask the question of a particular date, which is what a
panel needs.

## Usage

``` r
country_groups(group = NULL, as_of = NULL)
```

## Arguments

- group:

  One or more group names: any of `"EU"`, `"OECD"`, `"G7"`, `"G20"`,
  `"BRICS"`, `"ASEAN"`, `"EFTA"`, `"Commonwealth"`, `"OPEC"`,
  `"EuroZone"`, `"NATO"`, `"Mercosur"`, `"GCC"`, `"Nordic"`,
  `"Visegrad"`. If `NULL`, the whole table is returned.

- as_of:

  A date (or a year) at which to evaluate membership. `NULL` (default)
  uses the current snapshot. **A bare year means 1 January of that
  year**, not "at some point during it": `as_of = 2013` is 2013-01-01,
  so Croatia – which joined the EU on 2013-07-01 – is not yet a member.
  Pass a `"YYYY-MM-DD"` string or a `Date` when the month matters. See
  the section below.

## Value

A tibble of `group`, `iso3c`, `country`; with `as_of`, also `from` and
`to`.

## Membership changes, and which groups are dated

A snapshot silently misstates any panel that spans an accession. An EU
panel over 2015-2020 either includes the United Kingdom throughout or
excludes it throughout, and both are wrong:

    "GBR" %in% country_groups("EU", as_of = 2016)$iso3c   # TRUE
    "GBR" %in% country_groups("EU", as_of = 2021)$iso3c   # FALSE

[country_groups_history](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_history.md)
carries dated membership for twelve groups: EU, EuroZone, NATO, OECD,
ASEAN, EFTA, GCC, Mercosur, Nordic, Visegrad, BRICS and G7.
Commonwealth, G20 and OPEC are **not** dated – their histories involve
suspensions, readmissions and contested dates that would have to be
sourced case by case, and a fabricated date is worse than an absent one.
Asking for `as_of` on those warns and falls back to the snapshot.

## See also

[`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md),
[country_groups_history](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_history.md),
[`country_timeline()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_timeline.md)

## Examples

``` r
country_groups("EU")
#> # A tibble: 27 × 3
#>    group iso3c country 
#>    <chr> <chr> <chr>   
#>  1 EU    AUT   Austria 
#>  2 EU    BEL   Belgium 
#>  3 EU    BGR   Bulgaria
#>  4 EU    HRV   Croatia 
#>  5 EU    CYP   Cyprus  
#>  6 EU    CZE   Czechia 
#>  7 EU    DNK   Denmark 
#>  8 EU    EST   Estonia 
#>  9 EU    FIN   Finland 
#> 10 EU    FRA   France  
#> # ℹ 17 more rows
country_groups(c("G7", "BRICS"))
#> # A tibble: 17 × 3
#>    group iso3c country             
#>    <chr> <chr> <chr>               
#>  1 BRICS BRA   Brazil              
#>  2 BRICS CHN   China               
#>  3 BRICS EGY   Egypt               
#>  4 BRICS ETH   Ethiopia            
#>  5 BRICS IND   India               
#>  6 BRICS IDN   Indonesia           
#>  7 BRICS IRN   Iran                
#>  8 BRICS RUS   Russia              
#>  9 BRICS ZAF   South Africa        
#> 10 BRICS ARE   United Arab Emirates
#> 11 G7    CAN   Canada              
#> 12 G7    FRA   France              
#> 13 G7    DEU   Germany             
#> 14 G7    ITA   Italy               
#> 15 G7    JPN   Japan               
#> 16 G7    GBR   United Kingdom      
#> 17 G7    USA   United States       
# the UK was a member in 2016 and not in 2021
nrow(country_groups("EU", as_of = 2016))
#> [1] 28
nrow(country_groups("EU", as_of = 2021))
#> [1] 27
```
