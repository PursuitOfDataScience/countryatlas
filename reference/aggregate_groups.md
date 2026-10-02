# Aggregate by dated group membership

Roll countries up to a group such as the EU or the OECD using the
members of each row's own year, not today's list. An "EU" series built
from the current 27 members misstates every year before 2020 and every
year before an accession; this builds it from whoever was a member at
the time, under the same coverage rule as
[`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md).

## Usage

``` r
aggregate_groups(
  data,
  value,
  groups,
  as_of = NULL,
  fun = "sum",
  weight = NULL,
  min_coverage = 2/3
)
```

## Arguments

- data:

  A country-level frame with an `iso3c` column, and a `year` column for
  a panel.

- value:

  The value column to aggregate (unquoted).

- groups:

  One or more group names (see
  [`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md)).

- as_of:

  `NULL` (default) uses each row's `year` when `data` has one (a bare
  year is 1 January of that year, as in
  [`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md)),
  and the current membership otherwise. A single date or year applies
  one membership to every row.

- fun, weight:

  As in
  [`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md).

- min_coverage:

  The smallest share of the group's members that has to report before an
  aggregate is computed. Default `2/3`, the World Bank's rule. `0`
  computes every group-year from whatever it has.

## Value

A tibble of `group` (and `year` for a panel), the aggregated value,
`n_countries` (members on that date), `n_reporting`, `coverage`, and for
a weighted mean `coverage_weighted`.

## Who counts as a member

Coverage is measured against the group's full membership on that date,
taken from
[country_groups_history](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_history.md),
not against the members that happen to be in `data`: a member with no
row is counted as missing. That is the difference from
[`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md),
which can only count what it is given. For `fun = "weighted_mean"` the
weighted share is computed over the members present, since an absent
member's weight is unknown. A group with no dated history (Commonwealth,
G20, OPEC) warns and uses the current membership for every year.

## See also

[`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md),
[`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md),
[country_groups_history](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_history.md)

## Examples

``` r
pan <- data.frame(iso3c = rep(c("GBR", "FRA", "DEU", "HRV"), each = 2),
                  year = rep(c(2012, 2021), 4), gdp = 1:8)
# The United Kingdom counts in 2012 and not in 2021; Croatia the reverse.
aggregate_groups(pan, gdp, "EU", min_coverage = 0)
#> # A tibble: 2 × 6
#>   group  year   gdp n_countries n_reporting coverage
#>   <chr> <dbl> <int>       <int>       <int>    <dbl>
#> 1 EU     2012     9          27           3    0.111
#> 2 EU     2021    18          27           3    0.111
```
