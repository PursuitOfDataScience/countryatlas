# Describe an origin-destination table as a network

Node- and edge-level summaries of a bilateral flow table: who sends, who
receives, who is central. No `igraph` required – at country scale the
dense arithmetic is trivial.

## Usage

``` r
country_network(
  data,
  from,
  to,
  weight = NULL,
  origin = "country.name",
  top_n = 20
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

- top_n:

  How many edges to return in the `edges` element (default `20`, largest
  first). `Inf` for all.

## Value

A list of two tibbles:

- `nodes` – `iso3c`, `country`, `out_flow`, `in_flow`, `net_flow`,
  `out_degree`, `in_degree` and `strength_share` (the country's share of
  all flow, in or out).

- `edges` – `from`, `to`, `weight`, `share` and `reciprocity` (the
  opposite flow as a proportion of this one; `NA` where there is none).

## See also

[`flow_matrix()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_matrix.md),
[`od_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/od_map.md),
[`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md)

## Examples

``` r
od <- data.frame(
  from = c("China", "China", "Germany", "USA", "Mexico"),
  to   = c("USA", "Germany", "France", "Mexico", "USA"),
  value = c(500, 100, 80, 300, 320)
)
country_network(od, from, to, value)
#> $nodes
#> # A tibble: 5 × 8
#>   iso3c country    out_flow in_flow net_flow out_degree in_degree strength_share
#>   <chr> <chr>         <dbl>   <dbl>    <dbl>      <dbl>     <dbl>          <dbl>
#> 1 USA   United St…      300     820     -520          1         2         0.431 
#> 2 MEX   Mexico          320     300       20          1         1         0.238 
#> 3 CHN   China           600       0      600          2         0         0.231 
#> 4 DEU   Germany          80     100      -20          1         1         0.0692
#> 5 FRA   France            0      80      -80          0         1         0.0308
#> 
#> $edges
#> # A tibble: 5 × 5
#>   from  to    weight  share reciprocity
#>   <chr> <chr>  <dbl>  <dbl>       <dbl>
#> 1 CHN   USA      500 0.385       NA    
#> 2 MEX   USA      320 0.246        0.938
#> 3 USA   MEX      300 0.231        1.07 
#> 4 CHN   DEU      100 0.0769      NA    
#> 5 DEU   FRA       80 0.0615      NA    
#> 
```
