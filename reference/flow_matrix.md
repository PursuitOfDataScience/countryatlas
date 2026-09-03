# An origin-destination table as a matrix

Reshape a long bilateral table (trade, migration, flights, remittances)
into a square origin x destination matrix on the ISO spine, with both
country columns standardised. The natural input to a network analysis,
and to
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)`(type = "custom")`
– which is how "countries near each other in trade space" becomes a
spatial weights object.

## Usage

``` r
flow_matrix(
  data,
  from,
  to,
  weight = NULL,
  origin = "country.name",
  symmetric = FALSE,
  fill = 0
)
```

## Arguments

- data:

  An OD table.

- from, to:

  The origin and destination country columns (unquoted).

- weight:

  The flow column (unquoted). If omitted, every pair counts as 1.

- origin:

  How to read `from`/`to` (default `"country.name"`).

- symmetric:

  If `TRUE`, add the transpose so the matrix is undirected (default
  `FALSE`).

- fill:

  Value for pairs with no flow (default `0`).

## Value

A square numeric matrix with `iso3c` row and column names. Rows are
origins, columns destinations.

## See also

[`country_network()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_network.md),
[`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md),
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)

## Examples

``` r
od <- data.frame(
  from = c("China", "China", "Germany", "USA"),
  to   = c("USA", "Germany", "France", "Mexico"),
  value = c(500, 100, 80, 300)
)
flow_matrix(od, from, to, value)
#>     CHN DEU FRA MEX USA
#> CHN   0 100   0   0 500
#> DEU   0   0  80   0   0
#> FRA   0   0   0   0   0
#> MEX   0   0   0   0   0
#> USA   0   0   0 300   0
```
