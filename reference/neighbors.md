# A country's neighbours

Which countries border a given country (or countries) – a vectorised
lookup built on
[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md).

## Usage

``` r
neighbors(x, origin = "country.name", scale = "small", warn = TRUE)
```

## Arguments

- x:

  A vector of country names or codes.

- origin:

  How to read `x` (default `"country.name"`).

- scale:

  Natural Earth resolution to compute adjacency from. `"large"` needs
  the non-CRAN `rnaturalearthhires` package; see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md).

- warn:

  Whether to report values that do not resolve to a country (default
  `TRUE`). They match no border, so without this a typo is
  indistinguishable from a country that genuinely has no land neighbour.

## Value

A tibble with one row per (`iso3c`, `neighbor`) pair: the queried
country's `iso3c`, and each bordering country's `iso3c` and `country`
name (`neighbor`, `neighbor_country`). Countries with no land border
(islands, e.g. Japan, Madagascar) return zero rows.

## Pass a vector, don't loop

Every call rebuilds the whole world's adjacency from polygon topology,
so asking about one country costs the same as asking about all of them.
`x` is vectorised, and adding countries to a single call only adds the
filtering:

    countryatlas::neighbors(c("FRA", "DEU", "ESP"), origin = "iso3c")

Looping instead pays that rebuild once per country – for every bordering
country in the world, roughly two orders of magnitude more work than one
vectorised call. The same applies to
[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md),
which does the work.

## Name clash with igraph

`igraph` also exports a `neighbors()`, and it takes a graph and a vertex
rather than country names. Whichever package is attached later wins, so
if you use both – which
[`country_borders()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_borders.md)
suggests, for building a graph of the adjacency – qualify this one as
`countryatlas::neighbors()`.

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE)) {
  neighbors("France")
  neighbors(c("FRA", "JPN"), origin = "iso3c")   # Japan has no land border
}
#> # A tibble: 8 × 3
#>   iso3c neighbor neighbor_country
#>   <chr> <chr>    <chr>           
#> 1 FRA   SUR      Suriname        
#> 2 FRA   LUX      Luxembourg      
#> 3 FRA   ITA      Italy           
#> 4 FRA   BRA      Brazil          
#> 5 FRA   DEU      Germany         
#> 6 FRA   CHE      Switzerland     
#> 7 FRA   BEL      Belgium         
#> 8 FRA   ESP      Spain           
# }
```
