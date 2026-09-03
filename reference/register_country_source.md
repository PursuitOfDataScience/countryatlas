# Register a data source on the country spine

Teach `countryatlas` where to get indicators from. A source is a name
plus a `fetch` function; once registered it works with
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md),
[`add_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/add_indicator.md)
and
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md)
exactly like the built-in ones.

## Usage

``` r
register_country_source(
  name,
  fetch,
  meta = NULL,
  citation = NULL,
  key_col = "iso3c",
  key_type = "iso3c",
  cache = TRUE
)
```

## Arguments

- name:

  Short source name, used everywhere else (e.g. `"wdi"`).

- fetch:

  A function `(indicator, countries, years)` returning a tidy data
  frame. See the contract below.

- meta:

  Optional one-line description of the provider.

- citation:

  Optional citation string; surfaced by
  [`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md)
  so users can credit the data.

- key_col:

  The country-key column `fetch` returns (default `"iso3c"`). A column
  *name*, not a coding scheme.

- key_type:

  How to read that column: any
  [`countrycode::countrycode()`](https://rdrr.io/pkg/countrycode/man/countrycode.html)
  origin scheme (default `"iso3c"`). Set it to `"country.name"` for a
  source keyed on country names.

- cache:

  Whether results should be memoised for the session (default `TRUE`).

## Value

Invisibly, the source name.

## Details

This is deliberately a registry rather than more `Suggests`. It means a
provider with no CRAN package – V-Dem, the IMF, the World Inequality
Database – is reachable without this package depending on anything, and
it means an internal or proprietary feed is a first-class citizen.

## The fetch contract

`fetch(indicator, countries, years)` must return a data frame with:

- a country key column (named `key_col`, holding `key_type` values –
  normally an `iso3c` column of `iso3c` codes),

- a `year` column (integer) *if* the data is a panel,

- one column per requested indicator, named after the indicator, and

- one row per key – `iso3c` for a cross-section, `iso3c` and `year` for
  a panel.

The key has to be unique because
[`add_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/add_indicator.md)
joins on it: a repeated key multiplies the caller's rows, so it is
reported rather than joined in silence. Aggregate before returning if
the provider serves several rows per country-year.

`countries` is a character vector of `iso3c` codes or `NULL` for all;
`years` is a numeric vector or `NULL` for the provider's default.
Returning extra columns is fine – they travel through. Anything the
provider cannot serve should come back as `NA`, not as a missing row,
wherever that is cheap to arrange.

## See also

[`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md),
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md),
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md)

## Examples

``` r
# A trivial in-memory source
register_country_source(
  "demo",
  fetch = function(indicator, countries = NULL, years = NULL) {
    data.frame(iso3c = c("USA", "FRA"), year = 2020L, demo_value = c(1, 2))
  },
  meta = "A toy source for the examples"
)
country_sources()
#> # A tibble: 6 × 7
#>   source   meta                        key_col key_type cache available citation
#>   <chr>    <chr>                       <chr>   <chr>    <lgl> <lgl>     <chr>   
#> 1 comtrade UN Comtrade bilateral trad… iso3c   iso3c    TRUE  TRUE      United …
#> 2 demo     A toy source for the examp… iso3c   iso3c    TRUE  TRUE      NA      
#> 3 eurostat Eurostat (via eurostat); E… iso3c   iso3c    TRUE  TRUE      Eurosta…
#> 4 oecd     OECD statistics (via OECD)  iso3c   iso3c    TRUE  TRUE      OECD. h…
#> 5 owid     Our World in Data (via owi… iso3c   iso3c    TRUE  TRUE      Our Wor…
#> 6 wdi      World Bank World Developme… iso3c   iso3c    TRUE  TRUE      World B…
fetch_indicator("demo", "demo_value")
#> # A tibble: 2 × 3
#>   iso3c  year demo_value
#>   <chr> <int>      <dbl>
#> 1 USA    2020          1
#> 2 FRA    2020          2

# A source keyed on country names rather than codes: `key_col` says which
# column holds the key, `key_type` says how to read it.
register_country_source(
  "demo_named",
  fetch = function(indicator, countries = NULL, years = NULL) {
    data.frame(country = c("United States", "Japan"), year = 2020L,
               demo_value = c(3, 4))
  },
  key_col = "country", key_type = "country.name",
  meta = "A toy name-keyed source"
)
fetch_indicator("demo_named", "demo_value")
#> # A tibble: 2 × 4
#>   country        year demo_value iso3c
#>   <chr>         <int>      <dbl> <chr>
#> 1 United States  2020          3 USA  
#> 2 Japan          2020          4 JPN  
```
