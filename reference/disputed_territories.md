# Disputed territories

Territories whose status is contested, recorded so that a map can say
so.

## Usage

``` r
disputed_territories
```

## Format

A tibble with 22 rows:

- territory:

  Common name of the territory.

- iso3c:

  ISO 3166-1 alpha-3 code where one exists, else `NA`. Most disputed
  territories have none, which is why they cannot appear in an
  `iso3c`-keyed dataset at all.

- administered_by:

  The party in de facto control, or `NA` where none is. An ISO 3166-1
  alpha-3 code where that party has one – see the note on codes below.

- claimed_by:

  Semicolon-separated claimants, coded as for `administered_by`.

- status:

  One of `"un_member"`, `"un_observer"`, `"partially_recognised"`,
  `"administered"` or `"claimed"`.

- note:

  One sentence of context, including why the row is here.

## Details

**This table records that a dispute exists and who the parties are. It
does not adjudicate, rank claims, or imply that any claim is better
founded than another.** Where it says "administered by" it means de
facto control as reported by the mapping sources the package already
uses (Natural Earth), not recognition, legitimacy or endorsement.

## The codes in `administered_by` and `claimed_by`

Mostly ISO 3166-1 alpha-3, so they join the `iso3c` spine directly – but
not entirely, and the exceptions are the point of the table. Six parties
here are entities ISO assigns no code to, and they are written with a
mnemonic placeholder instead: `ABK` (Abkhazia), `CYP-N` (Northern
Cyprus), `OST` (South Ossetia), `PMR` (Transnistria), `SAH` (the Sahrawi
Arab Democratic Republic) and `SOL` (Somaliland).

Five of them – `ABK`, `CYP-N`, `OST`, `PMR` and `SOL` – appear in
`administered_by` for the like-named territory, which has no ISO code of
its own: the entity administers itself and ISO codes neither. `SAH` is
the exception and worth knowing about: it appears only as a *claimant*,
of Western Sahara, which ISO does code (`ESH`) and which `MAR`
administers.

None of the six are ISO codes, so none will resolve through
[`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
or any other `iso3c` lookup. Filter them out with
`%in% country_codes()$iso3c` if you need a strictly ISO-keyed column.

## Scope

A documented subset, not the roughly 188 disputed areas the EU's
data-visualisation guidance counts. The selection criterion is
mechanical and checkable: territories that appear as a distinct unit or
a contested boundary in Natural Earth at 1:110m or 1:50m, **and** have
an ISO 3166-1 code, a widely-used user-assigned code, or a standard
"disputed" label in ISO, UN M49 or World Bank practice. That criterion
requires nobody to judge the merits.

## See also

[`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md),
[`check_dispute_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_dispute_coverage.md),
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)

## Examples

``` r
disputed_territories[, c("territory", "iso3c", "status")]
#> # A tibble: 22 × 3
#>    territory         iso3c status              
#>    <chr>             <chr> <chr>               
#>  1 Western Sahara    ESH   administered        
#>  2 Kosovo            XKX   partially_recognised
#>  3 Palestine         PSE   un_observer         
#>  4 Taiwan            TWN   partially_recognised
#>  5 Crimea            NA    administered        
#>  6 Northern Cyprus   NA    partially_recognised
#>  7 Abkhazia          NA    partially_recognised
#>  8 South Ossetia     NA    partially_recognised
#>  9 Jammu and Kashmir NA    claimed             
#> 10 Aksai Chin        NA    administered        
#> # ℹ 12 more rows
```
