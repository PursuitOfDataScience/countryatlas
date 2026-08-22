# Search World Bank indicators

A tidy, pipeable wrapper on
[`WDI::WDIsearch()`](https://rdrr.io/pkg/WDI/man/WDIsearch.html) for
discovering indicator codes.

## Usage

``` r
wdi_search(pattern, field = c("name", "indicator"), cache = NULL)
```

## Arguments

- pattern:

  A regular expression to search indicator names/codes for.

- field:

  Which field to search: `"name"` (default) or `"indicator"`.

- cache:

  Optional cached `WDIcache()` object; if `NULL`, WDI's bundled cache is
  used (no network).

## Value

A tibble of matching `indicator` codes and `name`s.

## Examples

``` r
# \donttest{
# Searches WDI's bundled indicator list, so this needs no connection.
wdi_search("CO2 emissions")
#> # A tibble: 42 × 2
#>    indicator      name                                                          
#>    <chr>          <chr>                                                         
#>  1 CC.CO2.EMSE.BF CO2 emissions by sector (Mt CO2 eq) - Bunker Fuels            
#>  2 CC.CO2.EMSE.BL CO2 emissions by sector (Mt CO2 eq) - Building                
#>  3 CC.CO2.EMSE.EH CO2 emissions by sector (Mt CO2 eq) - Electricity/Heat        
#>  4 CC.CO2.EMSE.EL CO2 emissions by sector (Mt CO2 eq) - Total excluding LUCF    
#>  5 CC.CO2.EMSE.EN CO2 emissions by sector (Mt CO2 eq) - Energy                  
#>  6 CC.CO2.EMSE.FE CO2 emissions by sector (Mt CO2 eq) - Fugitive Emissions      
#>  7 CC.CO2.EMSE.IL CO2 emissions by sector (Mt CO2 eq) - Total including LUCF    
#>  8 CC.CO2.EMSE.IP CO2 emissions by sector (Mt CO2 eq) - Industrial Processes    
#>  9 CC.CO2.EMSE.LU CO2 emissions by sector (Mt CO2 eq) - Land-Use Change and For…
#> 10 CC.CO2.EMSE.MC CO2 emissions by sector (Mt CO2 eq) - Manufacturing/Construct…
#> # ℹ 32 more rows
# }
```
