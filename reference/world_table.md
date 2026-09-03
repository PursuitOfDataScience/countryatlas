# A publication-ready table from a map-ready frame

The tabular counterpart to
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md):
take the same curated frame and produce a ranked, formatted table
instead of a picture. Uses `gt` when it is installed and a plain tibble
otherwise, so it never becomes a hard dependency.

## Usage

``` r
world_table(
  data,
  value = NULL,
  top_n = 20,
  desc = TRUE,
  columns = NULL,
  engine = c("gt", "tibble"),
  title = NULL,
  subtitle = NULL
)
```

## Arguments

- data:

  A country-level or map-ready frame.

- value:

  The column to rank on (unquoted). `NULL` keeps every numeric column,
  does not sort, and omits the `rank` column – there is nothing to rank
  by, and `top_n` then takes an arbitrary slice (it warns when it does).

- top_n:

  How many rows (default `20`). `Inf` for all.

- desc:

  Sort descending (default `TRUE`).

- columns:

  Extra columns to keep, beyond `iso3c`, `country` and `value`.

- engine:

  `"gt"` (default, if installed) or `"tibble"`.

- title, subtitle:

  Optional table title and subtitle (`gt` only).

## Value

A `gt` table, or a tibble when `gt` is unavailable or
`engine = "tibble"`.

## See also

[`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md),
[`country_factsheet()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_factsheet.md),
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)

## Examples

``` r
world_table(countryatlas::world_snapshot$countries, gdp_per_capita,
            top_n = 5, engine = "tibble")
#> # A tibble: 5 × 4
#>    rank iso3c country     gdp_per_capita
#>   <int> <chr> <chr>                <dbl>
#> 1     1 MCO   Monaco             247170.
#> 2     2 BMU   Bermuda            122118.
#> 3     3 LUX   Luxembourg         104147.
#> 4     4 IRL   Ireland             94475.
#> 5     5 CHE   Switzerland         90067.
```
