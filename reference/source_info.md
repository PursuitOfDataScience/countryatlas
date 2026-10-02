# Where the numbers came from

Every fetch –
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md),
[`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md),
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md),
[`add_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/add_indicator.md),
and the population, deflator and PPP series that
[`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
[`deflate()`](https://pursuitofdatascience.github.io/countryatlas/reference/deflate.md)
and
[`to_ppp()`](https://pursuitofdatascience.github.io/countryatlas/reference/to_ppp.md)
fetch for themselves – records which provider each value column came
from, in what unit, from which release and when. `source_info()` reads
that record; `source_info<-` writes one for your own data, so a map of
it can say where it came from too.

## Usage

``` r
source_info(x)

source_info(x) <- value
```

## Arguments

- x:

  A data frame.

- value:

  A data frame with a `column` column naming columns of `x`, and any of
  `source`, `indicator`, `label`, `unit`, `provider_updated`,
  `fetched_at`, `vintage`, `licence` and `citation`; or `NULL` to remove
  the record.

## Value

`source_info()`: a tibble, one row per described column, with the ten
fields above (no rows when nothing is recorded). `source_info<-`: `x`
with the record attached.

## Which verbs keep it

The record is an attribute. dplyr's
[`filter()`](https://rdrr.io/r/stats/filter.html), `mutate()`,
`arrange()`, `select()` and `left_join()` (on the left-hand side) keep a
data frame's attributes, and `summarise()` drops them; the package's own
verbs carry the record explicitly, including
[`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md),
which builds its result from the geometry. The map verbs copy it into
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md),
whose print method names the source of the fill, and `footnote = "auto"`
adds a one-line source note to the caption.

## See also

[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md),
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md),
[`compare_vintages()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_vintages.md)

## Examples

``` r
d <- data.frame(iso3c = c("FRA", "DEU"), rate = c(7.3, 3.1))
source_info(d) <- data.frame(column = "rate", source = "My survey",
                             unit = "%", fetched_at = "2026-10-01")
source_info(d)
#> # A tibble: 1 × 10
#>   column source    indicator label unit  provider_updated fetched_at vintage
#>   <chr>  <chr>     <chr>     <chr> <chr> <chr>            <chr>      <chr>  
#> 1 rate   My survey NA        NA    %     NA               2026-10-01 NA     
#> # ℹ 2 more variables: licence <chr>, citation <chr>
```
