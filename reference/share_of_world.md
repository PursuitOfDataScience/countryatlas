# Each country's share of the world total

Adds a column giving each country's value as a share of the (year's)
world total – e.g. share of global emissions or GDP. Operates within
`year` when a panel is supplied. A `dplyr` grouping on `data` is ignored
– the denominator is always the world (or the year's) total, never the
group's.

## Usage

``` r
share_of_world(data, value, suffix = "_share")
```

## Arguments

- data:

  A country-level (or panel) data frame.

- value:

  The value column (unquoted).

- suffix:

  Suffix for the new column (default `"_share"`).

## Value

`data` with a share column added (a proportion in `[0, 1]`).

## Examples

``` r
df <- data.frame(iso3c = c("USA", "CHN"), co2 = c(5, 10))
share_of_world(df, co2)
#> # A tibble: 2 × 3
#>   iso3c   co2 co2_share
#>   <chr> <dbl>     <dbl>
#> 1 USA       5     0.333
#> 2 CHN      10     0.667
```
