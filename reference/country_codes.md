# The countrycode codelist as a tidy tibble

The whole
[countrycode::codelist](https://rdrr.io/pkg/countrycode/man/codelist.html)
reshaped into a tidy, pipeable lookup you can
[`filter()`](https://dplyr.tidyverse.org/reference/filter.html) /
`join()` directly – one row per country.

## Usage

``` r
country_codes(codes = NULL)
```

## Arguments

- codes:

  Optional character vector of column names to keep (in addition to
  `iso3c`). If `NULL`, a useful default subset is returned.

## Value

A tibble, one row per country.

## Examples

``` r
country_codes()
#> # A tibble: 249 × 10
#>    country      iso3c iso2c iso3n continent region region23 currency tld   flag 
#>    <chr>        <chr> <chr> <dbl> <chr>     <chr>  <chr>    <chr>    <chr> <chr>
#>  1 Afghanistan  AFG   AF        4 Asia      South… Souther… AFN      .af   🇦🇫   
#>  2 Albania      ALB   AL        8 Europe    Europ… Souther… ALL      .al   🇦🇱   
#>  3 Algeria      DZA   DZ       12 Africa    Middl… Norther… DZD      .dz   🇩🇿   
#>  4 American Sa… ASM   AS       16 Oceania   East … Polynes… USD      .as   🇦🇸   
#>  5 Andorra      AND   AD       20 Europe    Europ… Souther… EUR      .ad   🇦🇩   
#>  6 Angola       AGO   AO       24 Africa    Sub-S… Middle … AOA      .ao   🇦🇴   
#>  7 Anguilla     AIA   AI      660 Americas  Latin… Caribbe… XCD      .ai   🇦🇮   
#>  8 Antarctica   ATA   AQ       10 Antarcti… NA     NA       NA       .aq   🇦🇶   
#>  9 Antigua & B… ATG   AG       28 Americas  Latin… Caribbe… XCD      .ag   🇦🇬   
#> 10 Argentina    ARG   AR       32 Americas  Latin… South A… ARS      .ar   🇦🇷   
#> # ℹ 239 more rows
country_codes(c("iso2c", "continent", "currency"))
#> # A tibble: 249 × 5
#>    country           iso3c iso2c continent  currency
#>    <chr>             <chr> <chr> <chr>      <chr>   
#>  1 Afghanistan       AFG   AF    Asia       AFN     
#>  2 Albania           ALB   AL    Europe     ALL     
#>  3 Algeria           DZA   DZ    Africa     DZD     
#>  4 American Samoa    ASM   AS    Oceania    USD     
#>  5 Andorra           AND   AD    Europe     EUR     
#>  6 Angola            AGO   AO    Africa     AOA     
#>  7 Anguilla          AIA   AI    Americas   XCD     
#>  8 Antarctica        ATA   AQ    Antarctica NA      
#>  9 Antigua & Barbuda ATG   AG    Americas   XCD     
#> 10 Argentina         ARG   AR    Americas   ARS     
#> # ℹ 239 more rows
```
