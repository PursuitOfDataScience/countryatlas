# Auto-repair country names to their closest known match

The "act on it" companion to
[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md):
replaces unmatched country names with their closest known country name
(by string distance), but only when the match is confident enough, and
reports what it changed. Pipe the result into
[`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md)
/
[`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md).

## Usage

``` r
repair_country_names(
  x,
  threshold = 0.2,
  origin = "country.name",
  verbose = TRUE
)
```

## Arguments

- x:

  A vector of country names.

- threshold:

  Maximum string distance to accept a repair (0 = identical, 1 =
  unrelated). Lower is stricter; default `0.2`. Uses Jaro-Winkler when
  `stringdist` is installed, otherwise a length-normalised edit
  distance. The fallback repairs a subset of what Jaro-Winkler would: it
  charges two edits for a transposition, so at the default threshold
  `"Germny"` is repaired (one edit out of seven characters, 0.14) but
  `"Frnace"` is *not* (two out of six, 0.33). Jaro-Winkler scores that
  transposition 0.06 and repairs it.

  **Install `stringdist` if the repairs matter.** The two metrics choose
  the nearest known name independently, so they can land on *different
  countries*, not merely on fewer of them: `"Libia"` is repaired to
  Liberia with `stringdist` and to Libya without it, and both are
  accepted at the default threshold. Neither metric is uniformly better
  – Jaro-Winkler also repairs `"Maroco"` to Monaco rather than Morocco –
  which is the real reason to check the reported substitutions rather
  than to trust either. `verbose = TRUE` (the default) prints them, and
  they are attached as the `"repairs"` attribute for programmatic
  checking.

- origin:

  countrycode origin scheme (default `"country.name"`).

- verbose:

  Whether to message the substitutions made (default `TRUE`).

## Value

A character vector the same length as `x`, with confident misses
replaced by the closest known country name (others left unchanged). The
applied substitutions are attached as the attribute `"repairs"`.

## See also

[`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
for the report this acts on, and
[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
for dissolved entities, which are deliberately not repaired.

## Examples

``` r
repair_country_names(c("United States", "Brzil", "Germny"))
#> ✔ Repaired 2 country names:
#> • "Brzil -> Brazil" and "Germny -> Germany"
#> [1] "United States" "Brazil"        "Germany"      
#> attr(,"repairs")
#> # A tibble: 2 × 2
#>   from   to     
#>   <chr>  <chr>  
#> 1 Brzil  Brazil 
#> 2 Germny Germany
```
