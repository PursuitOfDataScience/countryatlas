# Is a country in a group?

A vectorised membership predicate built on
[`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md).

## Usage

``` r
in_group(x, group, origin = "country.name", as_of = NULL)
```

## Arguments

- x:

  A vector of country names or codes.

- group:

  A single group name (see
  [`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md)).

- origin:

  How to read `x` (default `"country.name"`).

- as_of:

  A date or year at which to evaluate membership; `NULL` (default) uses
  the current snapshot. A bare year means 1 January of that year, so use
  a `"YYYY-MM-DD"` string when an accession or exit falls mid-year. See
  [`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md).

## Value

A logical vector the same length as `x`. A value `origin` cannot resolve
to an ISO code answers `FALSE` – the same as a country that is genuinely
outside the group – so run
[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
first if you need to tell "not a member" from "not recognised".

## See also

[`country_groups()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups.md),
[country_groups_history](https://pursuitofdatascience.github.io/countryatlas/reference/country_groups_history.md)

## Examples

``` r
in_group(c("France", "United States", "Japan"), "EU")
#> [1]  TRUE FALSE FALSE
# membership is a function of time
in_group("United Kingdom", "EU", as_of = 2016)
#> [1] TRUE
in_group("United Kingdom", "EU", as_of = 2021)
#> [1] FALSE
```
