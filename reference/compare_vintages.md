# How much did a World Bank series change between releases?

The same indicator, the same year, from several releases of the World
Development Indicators side by side. Revisions between releases of one
database are large enough to change cross-country results (Johnson,
Larson, Papageorgiou & Subramanian 2013 show this for growth rates), and
they are easy to miss because a figure looks the same whichever release
it came from. This makes the check one call.

## Usage

``` r
compare_vintages(indicator, vintages, year = NULL, countries = NULL)
```

## Arguments

- indicator:

  One WDI indicator code, optionally named.

- vintages:

  Two or more releases, as in
  [`wdi_vintages()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_vintages.md)
  (`"2019-07"`), or `"current"` for the live release.

- year:

  The year to compare. `NULL` (default) uses the most recent year every
  release has values for.

- countries:

  Optional `iso3c` vector to restrict the comparison to.

## Value

A tibble, one row per country and release: `iso3c`, `country`,
`vintage`, `value`, and the `revision` and `rel_revision` from the first
release listed. A summary per release – the number of countries in both,
the median absolute and absolute relative revision, and the shares of
countries revised by more than 1% and 10% – is attached as the
`"countryatlas_revisions"` attribute.

## Units change between releases too

A series can be rebased between releases – GDP in constant 2010 US\$ in
one, constant 2015 US\$ in the next – and then every country is
"revised" by the change of base. The series label of each release is
compared, and a change of unit warns (class
`countryatlas_unit_mismatch`).

## References

Johnson, S., Larson, W., Papageorgiou, C. & Subramanian, A. (2013). Is
newer better? Penn World Table revisions and their impact on growth
estimates. *Journal of Monetary Economics* 60(2), 255-274.
[doi:10.1016/j.jmoneco.2012.10.022](https://doi.org/10.1016/j.jmoneco.2012.10.022)

## See also

[`wdi_vintages()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_vintages.md),
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md)

## Examples

``` r
# \donttest{
compare_vintages("SP.POP.TOTL", c("2019-07", "current"), year = 2015)
#> Warning: Release "2019-07" does not hold "SP.POP.TOTL".
#> ℹ The nearest releases are "2019-06", "2019-09", and "2019-04".
#> Warning: Fewer than two releases returned data, so there is nothing to compare.
#> # A tibble: 0 × 6
#> # ℹ 6 variables: iso3c <chr>, country <chr>, vintage <chr>, value <dbl>,
#> #   revision <dbl>, rel_revision <dbl>
# }
```
