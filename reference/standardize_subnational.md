# Standardise subnational region names to ISO 3166-2

The subnational counterpart to
[`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md):
resolve messy region names within a country to ISO 3166-2 codes, so
subnational data can be joined on a real key instead of on spelling.

## Usage

``` r
standardize_subnational(
  data,
  region,
  country,
  origin = "country.name",
  warn = TRUE
)
```

## Arguments

- data:

  A data frame with a region column.

- region:

  The region-name column (unquoted).

- country:

  The country column (unquoted), or a single country name/code applying
  to every row. ISO 3166-2 codes are only unique *within* a country, so
  this is required.

- origin:

  How to read `country` (default `"country.name"`).

- warn:

  Warn about regions that do not resolve (default `TRUE`).

## Value

`data` with `iso3c` and `iso_3166_2` columns added. Unresolved regions
get `NA`, never a guess.

## Coverage, stated plainly

Resolution uses the optional `regions` package's crosswalks – when the
installed version exposes a name-to-code pair this function recognises;
it says so once per session when it does not – plus exact and
case-insensitive matching against ISO 3166-2 names. Coverage is good for
Europe (where NUTS and ISO 3166-2 are both well maintained) and patchy
elsewhere. This function will return `NA` rather than a
plausible-looking wrong code, and
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)
on the result is the right next step.

## See also

[`subnational_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/subnational_map.md),
[`nuts_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/nuts_geometry.md),
[`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md)

## Examples

``` r
# \donttest{
d <- data.frame(region = c("Bavaria", "Hesse", "Nowhere"), value = 1:3)
if (requireNamespace("regions", quietly = TRUE)) {
  standardize_subnational(d, region, country = "Germany")
}
#> ! The installed regions (0.1.8) exposes no name-to-code crosswalk this function
#>   can use.
#> ℹ Only exact and case-insensitive ISO 3166-2 name and code matches will
#>   resolve; region names will not.
#> This message is displayed once per session.
#> Warning: 3 regions did not resolve to an ISO 3166-2 code:
#> • "Bavaria", "Hesse", and "Nowhere"
#> ℹ Coverage is best in Europe; see the section in
#>   `?countryatlas::standardize_subnational()`.
#>    region value iso3c iso_3166_2
#> 1 Bavaria     1   DEU       <NA>
#> 2   Hesse     2   DEU       <NA>
#> 3 Nowhere     3   DEU       <NA>
# }
```
