# Pre-flight country-match report

A report on what will and will not match before you trust the map: the
input, its `iso3c`, whether it `matched`, whether it is a `historical`
(dissolved) entity, and a `suggestion` (the closest known country name
by string distance) for misses. Surfaced automatically by
[`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md).

## Usage

``` r
check_country_match(
  x,
  origin = "country.name",
  custom_match = country_overrides(),
  suggest = TRUE
)
```

## Arguments

- x:

  A vector of country names or codes.

- origin:

  How to read `x` (any countrycode origin scheme).

- custom_match:

  Overrides applied before matching (default
  [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)).

- suggest:

  Whether to compute closest-name suggestions for misses (requires the
  optional `stringdist` package; default `TRUE`).

## Value

A tibble with columns `input`, `iso3c`, `matched`, `historical`,
`suggestion`.

## Details

The `historical` flag matters even for rows that *matched*: countrycode
silently resolves `"USSR"` to Russia's `RUS`, so Soviet-era data becomes
Russian data without a warning. Rows flagged `historical` should usually
be routed through
[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
instead.

## See also

[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
for resolving the entities this flags as `historical` to their successor
states, and
[`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md)
for applying the `suggestion` column automatically.

## Examples

``` r
check_country_match(c("USA", "Cote d'Ivoire", "Yugoslavia", "Wakanda"))
#> # A tibble: 4 × 5
#>   input         iso3c matched historical suggestion
#>   <chr>         <chr> <lgl>   <lgl>      <chr>     
#> 1 USA           USA   TRUE    FALSE      NA        
#> 2 Cote d'Ivoire CIV   TRUE    FALSE      NA        
#> 3 Yugoslavia    NA    FALSE   TRUE       Yugoslavia
#> 4 Wakanda       NA    FALSE   FALSE      Canada    
# "USSR" matches (to RUS!) but is flagged historical:
check_country_match("USSR")
#> # A tibble: 1 × 5
#>   input iso3c matched historical suggestion
#>   <chr> <chr> <lgl>   <lgl>      <chr>     
#> 1 USSR  RUS   TRUE    TRUE       NA        
```
