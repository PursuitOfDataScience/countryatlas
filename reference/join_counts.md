# Join counts: do neighbours share a category?

For a categorical variable – income group, region, a yes/no – count the
neighbouring pairs whose two countries fall in the same category, and
compare each count with what random labelling would give. Many more
same-category joins than chance is clustering; fewer is a checkerboard.

## Usage

``` r
join_counts(data, value, weights = NULL, n_perm = 999)
```

## Arguments

- data:

  A country-level frame with `iso3c`.

- value:

  The categorical column (unquoted): a factor, character or logical.

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object; `NULL` (default) is k-nearest neighbours (k = 5). A pair is
  joined when either country lists the other as a neighbour.

- n_perm:

  Permutations of the labels for the p-values (default `999`).

## Value

A tibble with one row per category: `category`, `n` (countries in it),
`joins` (pairs within it), `expected` and `sd` (under permutation), `z`,
and `p_value` (two-sided). Its `"n_joins"` attribute is the number of
joined pairs.

## References

Cliff, A. D. & Ord, J. K. (1981). *Spatial Processes: Models and
Applications*. Pion.

## See also

[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
for a numeric variable

## Examples

``` r
snap <- countryatlas::world_snapshot$countries
join_counts(snap, income, n_perm = 199)
#> # A tibble: 5 × 7
#>   category                n joins expected    sd     z p_value
#>   <chr>               <int> <int>    <dbl> <dbl> <dbl>   <dbl>
#> 1 High income            80   146    85.0   5.91 10.3    0.005
#> 2 Low income             26    33     8.77  2.57  9.42   0.005
#> 3 Lower middle income    54    65    38.3   5.42  4.93   0.005
#> 4 Not classified          1     0     0     0    NA      1    
#> 5 Upper middle income    54    61    38.8   4.80  4.63   0.005
```
