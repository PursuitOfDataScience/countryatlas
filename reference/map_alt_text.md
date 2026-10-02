# Describe a map in words, for alt text

A text description of a map drawn by the package, computed from the
final plot – its projection, its fill scale and the data it draws – so
it stays true when the plot is modified afterwards. Every map verb sets
it as the plot's alt text (`labs(alt =)`), which
[`ggplot2::get_alt_text()`](https://ggplot2.tidyverse.org/reference/get_alt_text.html)
returns and which knitr, Quarto and Shiny can pass to a screen reader.

## Usage

``` r
map_alt_text(p, level = 2)
```

## Arguments

- p:

  A map from one of the package's map verbs.

- level:

  `1` or `2` (default).

## Value

A single string.

## Details

The levels follow Lundgard & Satyanarayan (2022). **Level 1** describes
the construction: the kind of map, the projection, what the fill shows
and how it is classified, and how many countries have data. **Level 2**
adds statistics: the three highest and three lowest countries, the share
missing, and the continent with the highest median. Levels 3 and 4 –
trends, and what the map means – are the author's to write; add them to
the text this returns.

knitr does not ask ggplot2 for alt text when a chunk sets none, so in R
Markdown set it on the chunk, from a plot built in an earlier chunk:
`fig.alt = countryatlas::map_alt_text(p)`.

## References

Lundgard, A. & Satyanarayan, A. (2022). Accessible visualization via
natural language descriptions: a four-level model of semantic content.
*IEEE Transactions on Visualization and Computer Graphics* 28(1),
1073-1083.
[doi:10.1109/TVCG.2021.3114770](https://doi.org/10.1109/TVCG.2021.3114770)

## See also

[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
p <- world_map(attach_geometry(snap), gdp_per_capita)
map_alt_text(p)
#> [1] "Choropleth map of GDP per capita (constant 2015 US$) (gdp_per_capita) by country, Equal Earth projection. Coloured in 5 quantile classes from 269 to 247K. 199 of 238 countries have data. Highest: Monaco (247K), Bermuda (117K), Luxembourg (104K). Lowest: Burundi (269), Afghanistan (374), Central African Republic (390). Europe has the highest median (22.7K). 16% of countries have no data."
ggplot2::get_alt_text(p)
#> [1] "Choropleth map of GDP per capita (constant 2015 US$) (gdp_per_capita) by country, Equal Earth projection. Coloured in 5 quantile classes from 269 to 247K. 199 of 238 countries have data. Highest: Monaco (247K), Bermuda (117K), Luxembourg (104K). Lowest: Burundi (269), Afghanistan (374), Central African Republic (390). Europe has the highest median (22.7K). 16% of countries have no data."
# }
```
