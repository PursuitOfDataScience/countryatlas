# Classify countries as they were classified at the time

Add the World Bank's income group, region or lending category to a
frame, as in force on a date – each row's own `year`, by default – from
the bundled
[country_classifications](https://pursuitofdatascience.github.io/countryatlas/reference/country_classifications.md).
A panel spanning 2000 to 2026 gets the income group each country had in
each year, not today's list painted across every year, and the July 2025
move of Afghanistan and Pakistan from South Asia into the Middle East
and North Africa region falls where it happened.

## Usage

``` r
classify_countries(
  data,
  schemes = c("income", "region"),
  as_of = NULL,
  basis = c("in_effect", "data_year")
)
```

## Arguments

- data:

  A frame with an `iso3c` column, and a `year` column for a panel.

- schemes:

  Which classifications to add: any of `"income"`, `"region"` and
  `"lending"`. Each becomes a column of that name.

- as_of:

  `NULL` (default) classifies each row as of its `year`, or as of today
  when there is no `year` column. Otherwise one date or year for every
  row, or one per row; a bare year means 1 January of that year, as in
  [`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md).

- basis:

  For income: `"in_effect"` (default) gives the class in force on the
  date; `"data_year"` gives the class *computed from* that year's
  income, which is published two fiscal years later. See below.

## Value

`data` with the requested columns – `income` a factor in income order,
`region` and `lending` character – `NA` where the table has no
classification for that country on that date (a country not yet a
member, or a date before the table begins). Each added column carries a
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md)
record naming the World Bank source and the fiscal years used.

## The fiscal-year rule

The World Bank classifies each economy once a year, on 1 July, and the
class holds for its fiscal year: fiscal year *t* runs from 1 July *t*-1
to 30 June *t*, and its classification is set from GNI per capita (Atlas
method) for calendar year *t*-2.

So for a row dated 2020, `basis = "in_effect"` reads 1 January 2020,
which falls in fiscal year 2020 (1 July 2019 to 30 June 2020), whose
classes were computed from 2018 incomes. `basis = "data_year"` reads the
class computed from 2020 incomes instead, which is fiscal year 2022's
(in force from 1 July 2021). The first answers "how was this country
treated at the time"; the second "where did this year's income put it".
Regions and lending categories have no data year and are always read as
in force on the date.

## See also

[country_classifications](https://pursuitofdatascience.github.io/countryatlas/reference/country_classifications.md),
[`in_group()`](https://pursuitofdatascience.github.io/countryatlas/reference/in_group.md),
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)

## Examples

``` r
pan <- data.frame(iso3c = c("VNM", "VNM", "PAK", "PAK"),
                  year = c(2026, 2027, 2025, 2026))
classify_countries(pan, c("income", "region"))
#>   iso3c year              income
#> 1   VNM 2026 Lower middle income
#> 2   VNM 2027 Upper middle income
#> 3   PAK 2025 Lower middle income
#> 4   PAK 2026 Lower middle income
#>                                              region
#> 1                               East Asia & Pacific
#> 2                               East Asia & Pacific
#> 3                                        South Asia
#> 4 Middle East, North Africa, Afghanistan & Pakistan

# The class computed from a year's income, two fiscal years on:
classify_countries(data.frame(iso3c = "VNM", year = 2024), "income",
                   basis = "data_year")
#>   iso3c year              income
#> 1   VNM 2024 Lower middle income
```
