# State which map convention you are using

Disputed territories are drawn differently by different conventions, and
a map that does not say which one it used is making a choice silently.
This sets the session's convention so
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
can record it and
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)
can report it.

## Usage

``` r
dispute_policy(policy = NULL)
```

## Arguments

- policy:

  One of:

  - `"none"` (default) – no convention stated. Maps carry no dispute
    annotation, exactly as before.

  - `"de_facto"` – boundaries as administered on the ground, which is
    what Natural Earth (and therefore this package's geometry) uses.

  - `"de_jure"` – boundaries as claimed. The package does **not** ship
    de jure geometry; selecting this records the intent and warns that
    the shapes drawn are still de facto.

  - `"neutral"` – disputed areas marked as disputed rather than
    assigned.

  Called with no argument, returns the current policy.

## Value

The policy in effect, invisibly when setting.

## What this does and does not do

It records a choice and makes it visible. It does not redraw any
boundary, and selecting `"de_jure"` will not give you claimed-boundary
geometry, because the package does not have any – Natural Earth's
auxiliary claim lines are not bundled. Anyone publishing under an
institutional convention should verify the shapes against that
institution's own basemap rather than trusting a setting.

## See also

[disputed_territories](https://pursuitofdatascience.github.io/countryatlas/reference/disputed_territories.md),
[`check_dispute_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_dispute_coverage.md),
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)

## Examples

``` r
old <- dispute_policy()
dispute_policy("neutral")
dispute_policy()
#> [1] "neutral"
dispute_policy(old)
```
