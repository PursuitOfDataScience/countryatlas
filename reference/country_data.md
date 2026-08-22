# Lightweight one-row-per-country table

The analysis counterpart to
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md):
no polygons, one tidy row per country (`iso3c`, `iso2c`, `country`,
classifications and the requested indicators). This is what you actually
`join()` /
[`mutate()`](https://dplyr.tidyverse.org/reference/mutate.html) /
[`summarise()`](https://dplyr.tidyverse.org/reference/summarise.html) /
[`rank()`](https://rdrr.io/r/base/rank.html) on; attach geometry only at
draw time with
[`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md).

## Usage

``` r
country_data(
  year,
  indicator = NULL,
  latest = FALSE,
  panel = FALSE,
  classify = c("income", "continent", "region"),
  cache = TRUE,
  language = "en",
  parallel = TRUE
)
```

## Arguments

- year:

  A single year or a range (with `panel = TRUE`).

- indicator:

  A named character vector of WDI codes (or `NULL` for none).

- latest:

  Use the most recent non-`NA` value per country (single year).

- panel:

  Return a panel keyed on `iso3c` + `year` (implied when `year` spans
  multiple years).

- classify:

  Which classifications to add.

- cache:

  Whether to use the WDI cache.

- language:

  WDI language code.

- parallel:

  Whether to fetch indicators in parallel. Ignored when the cache is
  memory-only; see
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md).

## Value

A tibble, one row per country (or per country-year for a panel).

`iso3c` is the stable key; `country` is a *label* and its spelling
depends on where the row came from. A successful fetch carries the World
Bank's names ("Korea, Rep.", "Congo, Dem. Rep."), while the country
spine used when the fetch returns nothing carries the `countrycode`
names ("South Korea", "Congo - Kinshasa") – as do
[`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md),
[`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md)
and the rest of the package. Match on `iso3c`, and relabel with
`convert_country(iso3c, to = "country")` if you need one consistent set.

## Examples

``` r
# \donttest{
country_data(2020, c(co2 = "EN.GHG.CO2.MT.CE.AR5"))
#> # A tibble: 216 × 7
#>    iso3c iso2c country             continent region              income      co2
#>    <chr> <chr> <chr>               <chr>     <chr>               <fct>     <dbl>
#>  1 AFG   AF    Afghanistan         Asia      Middle East, North… Low i…  12.1   
#>  2 ALB   AL    Albania             Europe    Europe & Central A… Upper…   4.57  
#>  3 DZA   DZ    Algeria             Africa    Middle East, North… Upper… 172.    
#>  4 ASM   AS    American Samoa      Oceania   East Asia & Pacific High …   0.0001
#>  5 AND   AD    Andorra             Europe    Europe & Central A… High …  NA     
#>  6 AGO   AO    Angola              Africa    Sub-Saharan Africa  Lower…  20.5   
#>  7 ATG   AG    Antigua and Barbuda Americas  Latin America & Ca… High …   0.326 
#>  8 ARG   AR    Argentina           Americas  Latin America & Ca… Upper… 168.    
#>  9 ARM   AM    Armenia             Asia      Europe & Central A… Upper…   6.91  
#> 10 ABW   AW    Aruba               Americas  Latin America & Ca… High …   0.489 
#> # ℹ 206 more rows
# }
```
