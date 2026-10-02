# Cite exactly what a map used

The references for the sources and methods behind one map: the data,
from its
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md)
record; the geometry; the projection; the classification; and the method
behind a value-suppressing palette, a value-by-alpha map, a ternary map,
historical borders or a false-discovery-rate LISA map. Cite these
alongside the package itself (`citation("countryatlas")`).

## Usage

``` r
map_citation(p, format = c("text", "bibtex"))
```

## Arguments

- p:

  A map from one of the package's map verbs.

- format:

  `"text"` (default), formatted references, or `"bibtex"`.

## Value

For `"text"`, a character vector, one reference per element; for
`"bibtex"`, a `Bibtex` object for a `.bib` file.

## See also

[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md),
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
p <- world_map(attach_geometry(snap), gdp_per_capita)
map_citation(p)
#> [1] "World Bank WDI (2026). “GDP per capita (constant 2015 US$).” Series\nNY.GDP.PCAP.KD; release 2026-07; accessed 2026-10-02; licence CC BY\n4.0."                                                                                                                        
#> [2] "Natural Earth (2024). _Natural Earth: Free vector and raster map data_.\nNatural Earth. Version 5.1.1, 1:50m admin-0 countries; public domain,\n<https://www.naturalearthdata.com/>."                                                                                  
#> [3] "Savric B, Patterson T, Jenny B (2019). “The Equal Earth map\nprojection.” _International Journal of Geographical Information\nScience_, *33*(3), 454-465. doi:10.1080/13658816.2018.1504949\n<https://doi.org/10.1080/13658816.2018.1504949>."                         
#> [4] "Brewer C, Pickle L (2002). “Evaluation of methods for classifying\nepidemiological data on choropleth maps in series.” _Annals of the\nAssociation of American Geographers_, *92*(4), 662-681.\ndoi:10.1111/1467-8306.00310 <https://doi.org/10.1111/1467-8306.00310>."
# }
```
