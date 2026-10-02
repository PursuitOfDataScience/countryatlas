# Map LISA clusters

The map of
[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md):
countries coloured by cluster type, with non-significant ones left
neutral. Hot spots (High-High) and cold spots (Low-Low) read
immediately; the off-diagonal categories are the spatial outliers.

## Usage

``` r
lisa_map(
  data,
  value,
  weights = NULL,
  n_perm = 9999,
  alpha = 0.05,
  p_adjust = c("fdr", "bonferroni", "holm", "none"),
  ...
)
```

## Arguments

- data:

  A map-ready frame (polygon or `sf`) with `iso3c`.

- value:

  The value column (unquoted).

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object; `NULL` (default) is `country_weights("knn", k = 5)`, as in
  [`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md).

- n_perm, alpha, p_adjust:

  Passed to
  [`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md).
  The significance mask uses the adjusted p-values, and the caption
  names the method.

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A `ggplot` object, with the
[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md)
table attached as the `"countryatlas_lisa"` attribute.

## Backend

Either backend, as
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md):
the frame decides, and both draw in Equal Earth unless `projection` is
passed on through `...`.

## See also

[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md),
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
set.seed(1)
attach_geometry(snap, geometry = "polygon") |>
  lisa_map(gdp_per_capita, weights = country_weights("knn", k = 5),
           n_perm = 99)

# }
```
