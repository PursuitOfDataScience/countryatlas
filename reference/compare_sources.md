# Do two sources agree?

Fetch the same indicator from several providers and put the answers side
by side. Sources disagree more often than people expect – different
vintages, PPP bases, territorial definitions, revision schedules – and
on the ISO spine the comparison is one join. This is the verb that turns
"I used OWID" into "I used OWID, and here is where it differs from the
World Bank".

## Usage

``` r
compare_sources(
  indicator,
  sources = c("wdi", "owid"),
  year,
  countries = NULL,
  tolerance = 0.05,
  allow_unit_mismatch = FALSE
)
```

## Arguments

- indicator:

  Either one indicator code used for every source, or a named character
  vector giving each source its own code:
  `c(wdi = "NY.GDP.PCAP.KD", owid = "gdp_per_capita")`.

- sources:

  Source names to compare (default `c("wdi", "owid")`).

- year:

  A single year.

- countries:

  Optional `iso3c` subset.

- tolerance:

  Relative difference above which a country counts as a disagreement
  (default `0.05`, i.e. 5%).

- allow_unit_mismatch:

  Compare anyway when the sources state different units (default
  `FALSE`). See below.

## Value

A tibble with one row per country: the value from each source,
`n_sources` (how many reported it), `rel_diff` (max relative spread) and
`disagrees`. The correlation, coverage and disagreement summary is
attached as the `"countryatlas_source_summary"` attribute, with each
source's stated unit.

## Different units are not a disagreement

GDP per capita in constant 2015 US dollars and in current international
dollars differ for every country, and calling that a disagreement
between the sources would be wrong. Each fetch records the unit its
provider states (see
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md));
when two of them state different units the comparison is refused with
class `countryatlas_unit_mismatch`, naming them. Pass
`allow_unit_mismatch = TRUE` to compare anyway – a ratio that is
constant across countries can still be worth seeing – and read
`rel_diff` accordingly. A source that states no unit is not checked.

## See also

[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md),
[`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md)

## Examples

``` r
if (FALSE) { # \dontrun{
cmp <- compare_sources(c(wdi = "NY.GDP.PCAP.KD", owid = "gdp_per_capita"),
                       sources = c("wdi", "owid"), year = 2020)
attr(cmp, "countryatlas_source_summary")
} # }
```
