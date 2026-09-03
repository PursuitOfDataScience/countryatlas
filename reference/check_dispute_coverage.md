# Which disputed territories does your data touch?

Cross-references your data against
[disputed_territories](https://pursuitofdatascience.github.io/countryatlas/reference/disputed_territories.md)
so a contested area does not pass unremarked. Reports both directions:
the disputed territories your data covers, and those it is silent about.

## Usage

``` r
check_dispute_coverage(data, quiet = FALSE)
```

## Arguments

- data:

  A frame with `iso3c`, or a character vector of codes.

- quiet:

  Suppress the console summary.

## Value

A tibble of every disputed territory the package knows about, with
`in_data` saying whether your data covers it. The scope caveat in
[disputed_territories](https://pursuitofdatascience.github.io/countryatlas/reference/disputed_territories.md)
applies: this is a documented subset, not every dispute in the world.

## See also

[disputed_territories](https://pursuitofdatascience.github.io/countryatlas/reference/disputed_territories.md),
[`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md),
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md)

## Examples

``` r
check_dispute_coverage(countryatlas::world_snapshot$countries)
#> ℹ 2 tracked disputed territories appear in the data, of 22 tracked.
#> • 15 have no ISO code at all and cannot appear in any iso3c-keyed dataset.
#>   Set a convention with `dispute_policy()` so the map says which one it used.
#> # A tibble: 22 × 7
#>    territory         iso3c administered_by claimed_by  status      note  in_data
#>    <chr>             <chr> <chr>           <chr>       <chr>       <chr> <lgl>  
#>  1 Western Sahara    ESH   MAR             MAR;SAH     administer… Non-… FALSE  
#>  2 Kosovo            XKX   XKX             XKX;SRB     partially_… User… FALSE  
#>  3 Palestine         PSE   PSE             PSE;ISR     un_observer UN n… TRUE   
#>  4 Taiwan            TWN   TWN             TWN;CHN     partially_… ISO … FALSE  
#>  5 Crimea            NA    RUS             UKR;RUS     administer… Anne… FALSE  
#>  6 Northern Cyprus   NA    CYP-N           CYP;TUR     partially_… Reco… FALSE  
#>  7 Abkhazia          NA    ABK             GEO;ABK     partially_… Reco… FALSE  
#>  8 South Ossetia     NA    OST             GEO;OST     partially_… Reco… FALSE  
#>  9 Jammu and Kashmir NA    NA              IND;PAK;CHN claimed     Divi… FALSE  
#> 10 Aksai Chin        NA    CHN             IND;CHN     administer… Admi… FALSE  
#> # ℹ 12 more rows
```
