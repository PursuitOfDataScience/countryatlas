# Disputed territories and worldviews

Every world map takes a position on disputed territory, including the
ones that think they do not. The package takes none of its own: it
records which disputes your data touches, lets you state your
convention, and draws a published point of view when you choose one.

``` r

check_dispute_coverage(world_snapshot$countries)
#> # A tibble: 22 × 7
#>    territory         iso3c administered_by claimed_by  status      note  in_data
#>    <chr>             <chr> <chr>           <chr>       <chr>       <chr> <lgl>  
#>  1 Western Sahara    ESH   MAR             MAR;SAH     administer… Non-… FALSE  
#>  2 Kosovo            XKX   XKX             XKX;SRB     partially_… User… TRUE   
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

[`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md)
states the convention, and the map verbs record it:

``` r

old <- dispute_policy("neutral")
dispute_policy()
#> [1] "neutral"
dispute_policy(old)
```

Natural Earth publishes its countries under 31 points of view at 1:10m.
Set one, by the viewing country’s ISO code, and the `sf` backend draws
it (the file is downloaded once into the package cache):

``` r

dispute_policy("de_jure", worldview = "IND")
world_map(attach_geometry(world_snapshot$countries, geometry = "sf"),
          gdp_per_capita)
dispute_policy(worldview = NA)                     # back to the default view
```
