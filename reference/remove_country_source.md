# Remove a registered data source

The counterpart to
[`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md).
Registering is permanent for the session, so without this there was no
way to undo one – which made any code that registers a source (an
example, a test, an exploratory script) leave the registry permanently
changed, and
[`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md)
report different rows afterwards.

## Usage

``` r
remove_country_source(source)
```

## Arguments

- source:

  One or more source names, as given to
  [`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md).

## Value

The names actually removed, invisibly.

## Details

The five built-in sources cannot be removed: they are what the package
documents, and dropping one would make
[`?fetch_indicator`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)
wrong. Pass `cache = FALSE` to a fetch instead if you want to bypass
one.

## See also

[`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md),
[`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md)

## Examples

``` r
register_country_source("scratch", function(indicator, ...) NULL)
"scratch" %in% country_sources()$source
#> [1] TRUE
remove_country_source("scratch")
"scratch" %in% country_sources()$source
#> [1] FALSE
```
