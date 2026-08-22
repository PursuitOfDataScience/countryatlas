# Resolve dissolved entities to their successor states

Historical data is full of countries that no longer exist – the USSR,
Yugoslavia, Czechoslovakia – and they poison naive joins twice over:
most are silently unmatched, and some are silently *mis*matched
(`countrycode` resolves `"USSR"` to Russia alone, so Soviet-era totals
quietly become Russian totals). `dissolve_country()` resolves a mixed
vector of historical and modern names against the curated
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md)
crosswalk: dissolved entities expand to one row per successor state
(one-to-many, dated), while modern names pass through as single rows –
so a whole messy column can be piped in unchanged.

## Usage

``` r
dissolve_country(x, warn = TRUE)
```

## Arguments

- x:

  A character vector of country names (historical and/or modern).

- warn:

  Whether to warn about names that match neither a historical entity nor
  a modern country (default `TRUE`).

## Value

A tibble with one row per (input, successor) pair: `input` (as given),
`historical` (canonical dissolved-entity name, `NA` for modern
countries), `dissolved` (year the entity ceased to exist, `NA` for
modern), `iso3c` and `country` (the successor state). Unmatched inputs
yield one row with `iso3c = NA`.

## See also

[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md)
for the crosswalk itself and the successor policy (e.g. Kosovo's
inclusion in the Yugoslavia list);
[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md),
whose `historical` column flags these entities;
[`repair_country_names()`](https://pursuitofdatascience.github.io/countryatlas/reference/repair_country_names.md),
which deliberately leaves them alone.

## Examples

``` r
dissolve_country(c("USSR", "Czechoslovakia", "France"))
#> # A tibble: 18 × 5
#>    input          historical     dissolved iso3c country     
#>    <chr>          <chr>              <int> <chr> <chr>       
#>  1 USSR           Soviet Union        1991 ARM   Armenia     
#>  2 USSR           Soviet Union        1991 AZE   Azerbaijan  
#>  3 USSR           Soviet Union        1991 BLR   Belarus     
#>  4 USSR           Soviet Union        1991 EST   Estonia     
#>  5 USSR           Soviet Union        1991 GEO   Georgia     
#>  6 USSR           Soviet Union        1991 KAZ   Kazakhstan  
#>  7 USSR           Soviet Union        1991 KGZ   Kyrgyzstan  
#>  8 USSR           Soviet Union        1991 LVA   Latvia      
#>  9 USSR           Soviet Union        1991 LTU   Lithuania   
#> 10 USSR           Soviet Union        1991 MDA   Moldova     
#> 11 USSR           Soviet Union        1991 RUS   Russia      
#> 12 USSR           Soviet Union        1991 TJK   Tajikistan  
#> 13 USSR           Soviet Union        1991 TKM   Turkmenistan
#> 14 USSR           Soviet Union        1991 UKR   Ukraine     
#> 15 USSR           Soviet Union        1991 UZB   Uzbekistan  
#> 16 Czechoslovakia Czechoslovakia      1993 CZE   Czechia     
#> 17 Czechoslovakia Czechoslovakia      1993 SVK   Slovakia    
#> 18 France         NA                    NA FRA   France      
# One-to-many: Yugoslavia expands to its successor territories
dissolve_country("Yugoslavia")
#> # A tibble: 7 × 5
#>   input      historical dissolved iso3c country             
#>   <chr>      <chr>          <int> <chr> <chr>               
#> 1 Yugoslavia Yugoslavia      1992 BIH   Bosnia & Herzegovina
#> 2 Yugoslavia Yugoslavia      1992 HRV   Croatia             
#> 3 Yugoslavia Yugoslavia      1992 MKD   North Macedonia     
#> 4 Yugoslavia Yugoslavia      1992 MNE   Montenegro          
#> 5 Yugoslavia Yugoslavia      1992 SRB   Serbia              
#> 6 Yugoslavia Yugoslavia      1992 SVN   Slovenia            
#> 7 Yugoslavia Yugoslavia      1992 XKX   Kosovo              
```
