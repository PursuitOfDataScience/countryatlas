# Great-circle origin-destination flow map

Draws great-circle arcs between country pairs from an origin-destination
table (trade, migration, flights, remittances), resolving both endpoints
to centroids automatically.

## Usage

``` r
flow_map(
  data,
  from,
  to,
  weight = NULL,
  origin = "country.name",
  arc_points = 50,
  projection = "equal_earth",
  footnote = "auto",
  n = deprecated()
)
```

## Arguments

- data:

  An OD table.

- from, to:

  The origin and destination country columns (unquoted; names or
  `iso3c`).

- weight:

  Optional column controlling arc width/alpha (unquoted).

- origin:

  How to read `from`/`to` (countrycode origin scheme).

- arc_points:

  Points per arc (default `50`): the smoothness of each great circle.

- projection:

  Map projection, as in
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  (default `"equal_earth"`). The arcs are great circles in any
  projection.

- footnote:

  The caption: `"auto"` (default) says how many flows were drawn, a
  string is used as given, `FALSE` adds nothing.

- n:

  **\[deprecated\]** Use `arc_points`.

## Value

A `ggplot` object.

## Backend

The polygon backend draws it, in `projection` (Equal Earth by default),
so it needs no `sf`.

## Examples

``` r
# \donttest{
od <- data.frame(from = c("China", "Germany"),
                 to = c("United States", "France"),
                 value = c(500, 200))
flow_map(od, from, to, value)

# }
```
