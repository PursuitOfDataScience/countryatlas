# Panels done right

A cross-section has one row per country. A panel has one row per country
and year, and almost every country fact is a fact about a *date*: who
belonged to the EU, which income group a country was in, which region
the World Bank put it in. Treating those as fixed attributes of a
country quietly paints today’s world over every year of the panel. This
vignette walks through the verbs that keep the dates attached.
Everything here runs offline.

## A small panel

``` r

pan <- expand.grid(iso3c = c("GBR", "FRA", "VNM", "PAK", "AFG"),
                   year = 2019:2026, stringsAsFactors = FALSE)
pan$gdp <- round(1000 * (1 + 0.03)^(pan$year - 2019) *
                   c(GBR = 42, FRA = 39, VNM = 3.5, PAK = 1.5, AFG = 0.5)[pan$iso3c])
head(pan)
#>   iso3c year   gdp
#> 1   GBR 2019 42000
#> 2   FRA 2019 39000
#> 3   VNM 2019  3500
#> 4   PAK 2019  1500
#> 5   AFG 2019   500
#> 6   GBR 2020 43260
```

## Joining two panels

[`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)
reconciles the country keys on both sides. When both tables carry a
`year`, joining on the country alone would pair every year of one with
every year of the other, so it joins on the year too, and says so:

``` r

pop <- expand.grid(iso3c = c("United Kingdom", "France", "Viet Nam"),
                   year = 2019:2026, stringsAsFactors = FALSE)
pop$population <- 1e6 * c(67, 68, 98)[match(pop$iso3c, unique(pop$iso3c))]
joined <- country_join(pan, pop, iso3c, iso3c, origin_x = "iso3c")
#> Joining on year as well as iso3c.
#> ℹ Pass `also_by = character()` to join on the country alone.
nrow(joined) == nrow(pan)
#> [1] TRUE
```

Pass `also_by = character()` to join on the country alone when one table
really is a cross-section to broadcast, and a named vector
(`also_by = c(year = "yr")`) when the year columns are named
differently.

## Membership as of each row

[`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md)
takes one date per row, so each row asks about its own year. The United
Kingdom left the EU on 31 January 2020:

``` r

uk <- pan[pan$iso3c == "GBR", ]
uk$eu <- in_group(uk$iso3c, "EU", origin = "iso3c", as_of = uk$year)
uk[, c("year", "eu")]
#>    year    eu
#> 1  2019  TRUE
#> 6  2020  TRUE
#> 11 2021 FALSE
#> 16 2022 FALSE
#> 21 2023 FALSE
#> 26 2024 FALSE
#> 31 2025 FALSE
#> 36 2026 FALSE
```

A bare year means 1 January of that year, so the UK is a member on 1
January 2020 and not on 1 January 2021. Suspensions are spells of their
own: Syria is not counted in the Arab League from 2011 to 2023.

``` r

in_group(rep("SYR", 3), "ArabLeague", origin = "iso3c", as_of = c(2010, 2015, 2024))
#> [1]  TRUE FALSE  TRUE
```

## Classifications as they were

The World Bank classifies every economy once a year, on 1 July, from its
gross national income two years earlier.
[`classify_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/classify_countries.md)
reads the dated table, so each row gets the class in force at its date:

``` r

classify_countries(pan[pan$iso3c == "VNM" & pan$year >= 2024, ], "income")
#>    iso3c year  gdp              income
#> 28   VNM 2024 4057 Lower middle income
#> 33   VNM 2025 4179 Lower middle income
#> 38   VNM 2026 4305 Lower middle income
```

Viet Nam was lower middle income until 30 June 2026. The class *computed
from* a year’s income is published two fiscal years later: Viet Nam’s
2025 income put it in the upper middle group, in force from 1 July 2026.

``` r

classify_countries(data.frame(iso3c = "VNM", year = 2025), "income",
                   basis = "data_year")
#>   iso3c year              income
#> 1   VNM 2025 Upper middle income
```

## The region that moved

On 1 July 2025 the World Bank moved Afghanistan and Pakistan from South
Asia into its Middle East and North Africa region, renamed “Middle East,
North Africa, Afghanistan & Pakistan”. A panel classified with today’s
list puts them there in 2019 too:

``` r

reg <- classify_countries(pan[pan$iso3c %in% c("PAK", "AFG") &
                                pan$year %in% c(2025, 2026), ], "region")
reg[, c("iso3c", "year", "region")]
#>    iso3c year                                            region
#> 34   PAK 2025                                        South Asia
#> 35   AFG 2025                                        South Asia
#> 39   PAK 2026 Middle East, North Africa, Afghanistan & Pakistan
#> 40   AFG 2026 Middle East, North Africa, Afghanistan & Pakistan
```

## Lags keyed on the year

[`lag_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md),
[`diff_by_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/lag_by_country.md)
and
[`growth_rate()`](https://pursuitofdatascience.github.io/countryatlas/reference/growth_rate.md)
look up the value a year earlier, not the previous row. On a gapped
panel the change across the gap is `NA` rather than a two-year change
under a one-year label:

``` r

gappy <- pan[pan$iso3c == "FRA" & pan$year != 2022, c("iso3c", "year", "gdp")]
growth_rate(gappy, gdp)[, c("year", "gdp_growth")]
#> # A tibble: 7 × 2
#>    year gdp_growth
#>   <int>      <dbl>
#> 1  2019    NA     
#> 2  2020     0.0300
#> 3  2021     0.0300
#> 4  2023    NA     
#> 5  2024     0.0300
#> 6  2025     0.0300
#> 7  2026     0.0300
```

`by = "row"` keeps the old behaviour, for a panel that is irregular by
design, and warns about the gaps.

## Aggregates that know what they are missing

A regional average over the countries that happen to report is a
different number from the region’s average.
[`aggregate_regions()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_regions.md)
and
[`aggregate_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/aggregate_groups.md)
report how much of each group is behind each value, and leave a group
out when too little of it is (`min_coverage`, two thirds by default):

``` r

aggregate_groups(world_snapshot$countries, gdp_per_capita,
                 groups = c("EU", "ASEAN", "SADC"), fun = "weighted_mean",
                 weight = population)
#> # A tibble: 3 × 6
#>   group gdp_per_capita n_countries n_reporting coverage coverage_weighted
#>   <chr>          <dbl>       <int>       <int>    <dbl>             <dbl>
#> 1 ASEAN          5105.          10          10        1                 1
#> 2 EU            34927.          27          27        1                 1
#> 3 SADC           1831.          16          16        1                 1
```

The coverage columns say which share of the group’s members, and of its
population when a weight is given, the number rests on. The small panel
above has two of the EU’s 28 members in 2019, so its EU figure is
refused rather than passed off as the EU’s:

``` r

aggregate_groups(pan, gdp, groups = "EU", as_of = 2019)
#> Warning in aggregate_groups(pan, gdp, groups = "EU", as_of = 2019): 1 group falls below the 67% coverage rule, so its gdp is NA:
#> • "EU (7%)"
#> ℹ An aggregate over part of a group is not the group's figure. Pass
#>   `min_coverage = 0` to compute it anyway; the coverage columns say how much
#>   stands behind each row.
#> # A tibble: 1 × 5
#>   group   gdp n_countries n_reporting coverage
#>   <chr> <dbl>       <int>       <int>    <dbl>
#> 1 EU       NA          28           2   0.0714
```
