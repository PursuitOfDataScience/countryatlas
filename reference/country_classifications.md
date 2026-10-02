# Dated World Bank classifications

The World Bank's income groups, regions and lending categories, each row
dated, so a country can be classified as it was on any day the table
covers.
[`classify_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/classify_countries.md)
reads it;
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
and
[`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md)
take their `income` and `region` from it, as of the current fiscal year.

## Usage

``` r
country_classifications
```

## Format

A tibble with one row per classification spell: `iso3c`, `scheme`
(`"wb_income"`, `"wb_region"` or `"wb_lending"`), `value`, `from` and
`to` (the spell runs from `from` up to but not including `to`; `NA`
means open-ended, or, for `from`, in force since before the table's
records begin), `source` and `note`.

- `wb_income`:

  One row per economy per World Bank fiscal year from FY1989 to FY2027,
  from the historical classification by income (OGHIST). Fiscal year *t*
  runs from 1 July *t*-1 to 30 June *t* and is set from GNI per capita
  for calendar year *t*-2; see
  [`classify_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/classify_countries.md).
  An economy the World Bank did not classify in a year has no row for
  it.

- `wb_region`:

  The current regions, with the July 2025 change dated: Afghanistan and
  Pakistan are in South Asia until 1 July 2025 and in "Middle East,
  North Africa, Afghanistan & Pakistan" from then on, and the other
  members of that region carry its former name, "Middle East & North
  Africa", until the same date. No earlier region change is recorded.

- `wb_lending`:

  The FY2027 lending categories (IDA, IBRD, Blend). Earlier years are
  not recorded.

The World Bank's codes for two former entities are recoded to ISO
3166-3's (its `YUG`, Serbia and Montenegro, is `SCG`; its `YUGf`,
Yugoslavia, is `YUG`), and the Channel Islands, which have no ISO code,
are left out. The fiscal year the table reaches is its `"vintage"`
attribute.

## Source

World Bank, "World Bank Country and Lending Groups" (CLASS) and the
historical classification by income (OGHIST), both licensed CC BY 4.0;
the July 2025 region change from the World Bank DataBank Metadata
Glossary. Built by `data-raw/country_classifications.R`, which checks
one class per economy per fiscal year, agreement with OGHIST's
thresholds sheet, and the current classes against the World Bank API.
