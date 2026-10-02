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
  [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_overrides.md)).

- suggest:

  Whether to compute closest-name suggestions for misses (requires the
  optional `stringdist` package; default `TRUE`).

## Value

A tibble with columns `input`, `iso3c`, `matched`, `historical`,
`method` and `suggestion`. `method` says how a name was matched, tier by
tier, each tried only for what is still unmatched: `"override"` (the
[`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_overrides.md)
table), `"regex_en"` (countrycode's English patterns), `"name_de"`,
`"name_es"`, `"name_fr"` and `"name_it"` (an exact match, ignoring case,
accents and punctuation, against countrycode's German, Spanish, French
and Italian names), `"cldr"` (the same against every name, short name
and variant in the Unicode CLDR tables countrycode carries, in every
language), `"ambiguous"` (a CLDR name for more than one country, which
is left unmatched) or `"none"`. Exact rather than countrycode's language
patterns, which are unanchored and matched Somaliland to Somalia. For an
`origin` other than a name it is `"code"`.

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
#> # A tibble: 4 × 6
#>   input         iso3c matched historical method   suggestion
#>   <chr>         <chr> <lgl>   <lgl>      <chr>    <chr>     
#> 1 USA           USA   TRUE    FALSE      regex_en NA        
#> 2 Cote d'Ivoire CIV   TRUE    FALSE      regex_en NA        
#> 3 Yugoslavia    NA    FALSE   TRUE       none     Yugoslavia
#> 4 Wakanda       NA    FALSE   FALSE      none     Canada    
# "USSR" matches (to RUS!) but is flagged historical:
check_country_match("USSR")
#> # A tibble: 1 × 6
#>   input iso3c matched historical method   suggestion
#>   <chr> <chr> <lgl>   <lgl>      <chr>    <chr>     
#> 1 USSR  RUS   TRUE    TRUE       regex_en NA        
```
