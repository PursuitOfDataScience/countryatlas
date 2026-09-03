# countryatlas 3.0.0

The whole of the roadmap tracked in
[#19](https://github.com/PursuitOfDataScience/countryatlas/issues/19), in one
release. 45 new exports and two new datasets take the package from "join World
Bank data to a map" to "join *anyone's* data, to the map as it was in 1950, and
say honestly what the picture does and does not support".

The version is 3.0.0 rather than 2.1.0 because three things change behaviour for
existing code: `world_map(projection = "mercator")` now produces a different
(and usable) map, `morans_i()` returns two more columns, and
`geom_country_labels()` takes `data` as its second argument. Details under
**Breaking changes**.

## Breaking changes

* **`geom_country_labels()` gains `data` as its second argument**, matching the
  `geom_*(mapping, data, ...)` convention every other ggplot2 geom follows. A
  call that passed `repel` positionally -- `geom_country_labels(aes(...),
  FALSE)` -- now binds that `FALSE` to `data` and must name it. Named calls are
  unaffected.
* **`morans_i()` returns `n_excluded` and `excluded`.** Code that assumed a
  five-column result will see seven. The statistic itself is unchanged.
* **`world_map(projection = "mercator")` draws a different map** -- see the bug
  fix below. It was previously unusable, so this is a fix rather than a
  regression, but the output does change.
* **`style = "binned"` draws different bins** in `world_map()`, `globe_map()`
  and `value_by_alpha_map()`. `n_bins` was silently ignored there (see the bug
  fix below), so the bin count and boundaries change for any existing call.
  `style = "quantile"` and `"jenks"` are unaffected.
* **`classification_report = TRUE` returns `NULL` for `style = "continuous"`**
  instead of a row-per-distinct-value table, and warns. Code that read the
  attribute after a continuous map got a table that described nothing; it now
  gets nothing, explicitly.
* `world_map()`'s new arguments were deliberately appended *after* `recenter`,
  so no existing positional call to it changes meaning.
* **`country_join()` and `country_join_all()` gain `warn`, defaulting to
  `TRUE`.** They now warn about country names that resolve to nothing, so code
  that joins on messy names will start emitting a warning it did not before.
  The join result is unchanged; pass `warn = FALSE` for the old silence.
* **`world_map(engine = "tmap")` now projects.** It took `projection` and
  `recenter` and drew in the frame's own CRS regardless (see the bug fix
  below), so every existing tmap map changes: the default is Equal Earth, as
  it already was on the ggplot2 engine. A bad projection name is now an error
  there rather than being ignored.
* **Five verbs now return a tibble rather than the class they were handed.**
  `to_ppp()`, `smooth_rates()`, `interpolate_missing()`, `spatial_lag()` and
  `rank_countries()` returned whatever arrived: a `data.frame` stayed a
  `data.frame`, and a grouped frame stayed grouped (see the bug fixes below).
  They now normalise, as their sibling verbs always did. Code that relied on
  `df[, "col"]` dropping to a vector, or on an inherited grouping surviving
  the call, changes.
* **`complete_years()` returns an `sf` frame when given one.** It previously
  dropped the class while leaving the geometry column in place, so a pipeline
  that repaired the result with `st_as_sf()` is now re-wrapping something that
  is already `sf` -- harmless, but no longer necessary.
* **A duplicated column name is now refused.** `per_capita()` and `to_ppp()`
  accepted a frame with two `gdp` columns and silently computed from the
  first; ten other verbs failed with a message about internals in tibble. All
  of them now reject it up front (see the bug fix below).
* **`region` is applied when `geometry = "none"`.** `world_data()` and
  `join_world()` ignored it on that branch and returned every country in the
  world (see the bug fix below), so a call passing both now gets fewer rows --
  the ones it asked for. A bounding box, having nothing to clip against, is
  refused rather than silently dropped.
* **Several backends now warn where they used to accept an argument and drop
  it** -- `scale` and `projection` on the polygon backend, the ggplot2-only
  arguments on the `tmap` and `mapgl` renderers, `title`/`subtitle` on
  `world_table(engine = "tibble")`, and `...` on two of `interactive_map()`'s
  engines. The drawings are unchanged; only the silence is. Code running under
  `options(warn = 2)` will now stop where it previously carried on.
* **Argument values are no longer partially matched.** Every exported function
  that takes a fixed set of choices now validates with `rlang::arg_match()`
  instead of `match.arg()`, so `style = "quant"` errors rather than resolving to
  `"quantile"`. The error names the argument, the function and the valid
  choices, and suggests the one you meant -- `match.arg()` reported only
  `'arg' should be one of ...`, naming neither. Spelled-out values are
  unaffected.

## Bug fixes

* **`top_n` went unvalidated in `world_table()` and `country_network()`.**
  `Inf` is the documented "no limit", which `check_number()` rejects, so the
  guard was a bare `is.finite()` -- and everything `is.finite()` rejects then
  skipped validation altogether. `top_n = "5"` and `top_n = NA` silently
  returned every row instead of five, and `top_n = NULL` failed on `if` with R's
  "argument is of length zero". Both now validate up front and still take `Inf`.
* **`world_table(subtitle = )` was dropped unless a `title` came with it.** gt
  draws the subtitle inside the header block that a title opens, so a lone
  subtitle had nowhere to go; it now says so instead of vanishing.
* **`value_by_alpha_map()` drew a half-lit map when opacity meant nothing.**
  The alpha scale had no `limits`, so it rescaled to whatever spread the frame
  happened to have; an `equalize` column with nothing usable collapsed to one
  value and ggplot2 placed it at the *midpoint* of `alpha_range`. The result
  read as "every country equally weighted" -- the one impression this verb
  exists to prevent. Opacity is now absolute (`limits = c(0, 1)`), so a frame
  with no usable equalising variable is drawn at the floor and says so, and two
  maps of different subsets are comparable.
* **`rate_check()` returned an all-`NA` `flagged` column in silence.** With no
  positive finite denominator anywhere, the tenth-percentile threshold is `NA`
  and every comparison against it is `NA` too -- so `sum(out$flagged)`, the
  obvious next step, came back `NA` rather than a count. It now says why.
* **`deflate()` returned an all-`NA` country without saying why.** A country
  with no usable deflator in `base_year` has nothing to rebase against, so every
  one of its values is `NA` -- correct arithmetic, but in the output
  indistinguishable from a country the source never covered. It now names them
  and suggests a base year the panel actually spans.
* **`od_map()` dropped a named origin without saying so.** A country that
  appears in the OD table only as a destination has no outflow to draw, so it
  was filtered out -- silently, leaving the caller to notice that they asked for
  four panels and got three. Named origins now warn (and point at
  `direction = "in"`); trimming the `origins = <n>` top-N list stays quiet,
  which is what top-N means.
* **`distance_between()` returned a silent `NA` for a name that is not a
  country.** Two causes produce an `NA` distance and only one is the documented
  gap: a country with no bundled centroid is expected -- `?distance_between`
  says so, and `country_weights()` already reports it -- while a value that
  resolves to no country at all is a mistake, usually the wrong `origin`, and
  handed back a column of `NA` with nothing said. The second is now reported,
  naming the values and the `origin` in force; the documented gap stays quiet.
* **`simplify_geometry()` and `theme_world_map()` never validated their first
  argument.** Both check their *second* one carefully.
  `simplify_geometry()` handed a non-spatial object straight to rmapshaper,
  leaking "no applicable method for 'ms_simplify' applied to an object of class
  NULL" -- rmapshaper's generic rather than the argument -- and failed
  differently again through the `sf::st_simplify()` fallback, so the message
  depended on which optional package the caller happened to have.
  `theme_world_map()` got base R's bare "non-numeric argument to binary
  operator". Found by calling all 102 exports with degenerate input and
  classifying which errors were the package's own.
* **Three verbs joined on an unstandardised key and said nothing.** Lowercase,
  mixed-case and padded `iso3c` values match nothing, so `attach_geometry()`
  drew every country as no-data, `tile_map()` drew every tile grey, and
  `add_indicator()` attached a column of pure `NA` -- each of which reads as a
  coverage problem, or as the provider having no data, rather than as a key
  problem. An *unmatched* code stays quiet, because the basemap genuinely holds
  fewer countries than the snapshot; matching *nothing* now says so and points
  at `standardize_country()`, which normalises case and whitespace.
  `attach_geometry(year = )` already reported its match rate; the ordinary
  branches did not.
* **`complete_years()` also leaked one on a *missing* `year`.** It infers the
  span with `seq(min(year), max(year))`, so a single `NA` produced base R's
  "'from' must be a finite number", naming neither the column nor the package.
  The `years` argument has been checked for `NA` all along; the column it
  defaults from had not, and one blank cell in a CSV is enough to hit it.
* **`complete_years()` leaked an internal error on a non-numeric `year`.** Its
  `years` *argument* was checked carefully but the `year` *column* was not, so a
  character one surfaced as dplyr's "Can't join `x$year` with `y$year` due to
  incompatible types" -- naming dplyr's internals rather than the column -- and
  a factor got base R's bare "'min' not meaningful for factors". Both come
  straight out of a CSV read.
* **`country_factsheet()` printed `NA` as the country name** for any code with
  no `country_meta` row. The fallback was `first_or_na(row$country) %||% iso`,
  but `%||%` only replaces `NULL` and `first_or_na()` returns `NA_character_`,
  so it never fired: `country_factsheet("Kosovo")` headed its output
  `NA (XKX)` while listing four real land neighbours underneath. It now falls
  back to the name the caller used.
* **`country_meta` had five blank capitals alongside 34 `NA`s.**
  `WDI_data` uses `""` for an unknown capital and it passed through
  unchanged, so `is.na(capital)` was wrong for Gibraltar, Hong Kong, Israel,
  Macao and the Palestinian Territories, and the factsheet printed
  `capital: ` with nothing after it. Blank strings are now `NA`, in the
  dataset and in the script that builds it.
* **`Suggests: testthat` understated its minimum.** The suite has used
  `expect_no_error()` (testthat 3.1.5) for some time and now uses
  `expect_no_match()` (3.2.0), while `DESCRIPTION` still asked only for 3.0.0.
  Bumped to `>= 3.2.0`.
* **`rank_countries()` and `share_of_world()` said nothing about a repeated
  country-year.** `interpolate_missing()` and `complete_years()` already report
  that shape, but the two verbs that *aggregate across* rows did not -- and
  their output is the harder to reconcile. Given a frame with `USA`-2020
  duplicated, `rank_countries()` returned the same country holding ranks 1
  **and** 3, and `share_of_world()` gave it shares of 0.1 and 0.7 against a
  world total that counted it twice. Both now report it, each naming its own
  consequence rather than the lag family's.
* **Four numeric-column verbs did not check that the column was numeric.**
  `country_network()` validates its `weight` with `check_numeric_col()`; the
  verbs shaped like it did not. `bubble_map()` and `flow_map()` reached
  ggplot2's bare `Discrete value supplied to a continuous scale`, and only at
  *build* time -- so the call returned happily and the failure surfaced when
  the plot was printed, naming neither the argument nor the column.
  `spike_map()` blamed the join (`No rows with a non-negative <col> joined to a
  centroid`) and `convergence_club()` blamed the panel (`Not enough countries
  with a complete series`), when in both cases the column simply was not a
  number. All four now refuse at the call, naming the column.
* **`fetch_indicator()` trusted a registered source's `key_col` claim.** When
  a source declared `key_col = "iso3c"` its codes were used verbatim, but the
  declaration is the source's claim rather than a guarantee -- and this is the
  package's public extension point. Lowercase codes (`"usa"`) passed through
  unchanged, a factor stayed a factor, and numeric UN M49 codes (`840`) sailed
  through as numbers, each producing rows that silently joined to nothing and
  read as "the provider has no data". The key is now standardised whatever the
  source claims (a no-op on codes that are already right), and values that are
  not usable as the declared key become `NA` *and* are named
  (`countryatlas_bad_key`).
* **A factor value column was read as its level indices.** `adapter_reshape()`
  coerced the provider's value column with `as.numeric()`, which on a factor
  returns level *indices*: a column of `factor("10", "20")` became `1, 2`.
  `check_numeric_col()` rejects a factor outright with precisely this advice
  (`as.numeric(as.character(x))`), and its comment notes how easily such a
  column happens -- but the adapters take theirs from a third party, so they
  cannot reject it and must not misread it either.
* **Every source path misread the provider's time column.** `...` forwards to the client, so the caller chooses its type:
  eurostat's `time_format = "num"` returns a numeric year and `"raw"` a
  character one, while the default is a `Date`. Each adapter assumed one shape.
  `fetch_eurostat()` failed on the other two with base R's opaque
  `invalid 'trim' argument` -- `format()` reading `"%Y"` as its `trim`
  argument. `fetch_oecd()` was worse, failing *silently*: `as.integer()` on a
  `Date` returned **18262**, the day count, as the year, and a quarterly
  `"2020-Q1"` became `NA`. Both now read the year from a date, a number, or a
  string leading with one, and say so when a value is not a year at all.

  The same bare `as.integer()` reached six sites, not two: `fetch_comtrade()`,
  whose `period` is `YYYYMM` for monthly data (so `"202001"` became the year
  202001); `adapter_reshape()` itself, which `fetch_owid()` reaches without
  preprocessing; and `fetch_indicator()` -- the *public extension point*, where
  the year is whatever a third-party fetch function returned. All six now share
  one reader.

  Two more sites outside the adapters took a year from the caller and read it
  the same wrong way. `audit_time_coverage()` turned a `Date` year column into
  day counts (`1990-01-01` -> 7305) and then flagged *both* USSR rows as
  post-dissolution -- silently wrong output from the one verb whose job is
  catching that class of mistake. And `deflate()` reported a `Date` `base_year`
  back as `` `base_year` 11323 is not in year ``, a number the caller never
  supplied; it now accepts a date, a number or a string, and names what it was
  actually given when it cannot.
* **The source adapters returned an empty frame in silence when no entity
  resolved.** `adapter_reshape()` resolves the provider's entity column with
  `suppressWarnings()` on purpose -- every Our World in Data or Eurostat
  response carries aggregate rows like `"World"` and `"EU27"` that are not
  countries and never resolve -- but that also swallowed a provider renaming
  its entities, or the wrong column being named. The result was zero rows and
  no explanation, sending the reader to check their own indicator code, while
  the same function takes care to explain an empty *input* a few lines earlier.
  Nothing resolving at all now aborts (`countryatlas_no_entities`), naming the
  entities it could not match. An empty result from the `countries`/`years`
  filters is unaffected -- those entities did resolve.
* **`bivariate_map()` leaked `classInt`'s "single unique value"** for a column
  with no variation. `classInt` needs two distinct values per axis to cut
  classes from, and a constant column reached it as a bare `simpleError` from a
  third-party package, naming neither the column nor the function nor anything
  to do about it. Both axes are now checked, naming the column and its distinct
  count.
* **`tile_map()` overstated its coverage**, the same way `bubble_map()` and
  `spike_map()` did. The bundled equal-area grid does not cover every code --
  Hong Kong and Macao have snapshot data and no tile -- so counting the input's
  coded countries as shown claimed 191 where the map could draw 189. Coverage
  is now measured against what the grid can actually place, and the
  `countryatlas_no_centroid` warning names the countries it cannot.
* **`per_capita()` returned `Inf` for a zero population, silently.**
  `deflate()` and `to_ppp()` were fixed for precisely this -- there is a test
  named *"an unusable deflator or PPP factor gives NA, not Inf"* whose comment
  records that `Inf` "propagated silently into every scale and summary
  downstream" -- but the most used function of the family never got the fix. A
  zero or missing population now yields `NA` and says so, matching its
  siblings. A *negative* population still passes through unchanged and
  silently, because that is pinned deliberately elsewhere in the suite --
  negative values are the caller's business and the arithmetic stays honest.
* **`country_weights()` built an edgeless graph without comment.**
  `country_weights("distance", cutoff_km = 1)` returned 239 countries and zero
  links, as did an all-zero custom matrix. Every statistic then refused to run
  with `Not enough connected countries with data` -- an error about the *data*,
  raised far from the `cutoff_km` or matrix that actually caused it. Building
  weights that link nothing now warns (`countryatlas_empty_weights`), naming
  the cause specific to the scheme.
* **`smooth_rates()` and `to_ppp()` returned all-`NA` columns in silence** --
  the same bug `rate_check()` already had fixed, kept by its two siblings. With
  no finite positive denominator every rate is `NA` and the smoothed column
  with it; with no finite positive conversion factor every converted value is
  `NA`. Correct arithmetic either way, but the output looked like a computation
  that had run rather than one with nothing to run on. Both now say so, and
  report a partial loss with a count.
* **`country_weights("custom")` validated only the row and column names**, so
  bad input leaked a bare base-R error from deep downstream instead of being
  refused where the caller could act. A character matrix reached `rowSums()` as
  `'x' must be numeric`; an `NA` entry was *accepted*, then killed any statistic
  built on it with `subscript out of bounds`; an `NA` endpoint in a long frame
  surfaced as `NAs are not allowed in subscripted assignments`; and an `NA`
  weight was accepted outright, silently turning every result into `NA`. All
  four are now refused at construction, naming the argument and the count.
  Numeric and logical matrices and long frames are unaffected -- and this is the
  path `vignette("honest-maps")` recommends for a non-geographic adjacency
  (trade volume, migration, shared language).
* **One `dplyr::filter()` referenced its columns bare.** The bounding-box
  branch of `world_geometry(geometry = "polygon")` filtered on `long`/`lat`
  rather than `.data$long`/`.data$lat` -- the only such site against twenty
  `.data$` uses elsewhere. A bare reference falls back to a variable of that
  name in the calling scope when the column is absent, so it can filter on the
  wrong thing where `.data$` errors plainly. With it converted,
  `utils::globalVariables()` no longer needs to declare `long` and `lat`;
  only `animate_world()`'s NSE default `time = year` remains.
* **`spin_globe()`'s example was never executed by anything.** It sat in
  `\dontrun{}`, which `R CMD check` skips even under `--run-donttest`, so the
  one example of the GIF pipeline was free to rot unnoticed. It needs no
  network -- only bundled data and `gifski`/`magick` -- so it is now
  `\donttest{}`, guarded on those packages and cut to six frames, which runs
  in about five seconds and is checked from here on.
* **`as_ggsql_source(format = "duckdb")` did not say who owns the connection
  it returns.** duckdb keeps its in-memory database alive until the handle is
  released, and neither `@return` nor `@param format` told the caller to close
  it -- while the `"parquet"` branch quietly closed the connection it opened.
  `?as_ggsql_source` now spells out all three lifecycles, and a connection the
  function opened itself is released if the write throws, so a failure cannot
  leave a handle nobody holds.
* **`sigma_convergence()` returned an empty or blank series in silence.** Its
  positive-value filter is documented -- `n` counts what survived -- but two of
  its outcomes were not. A column with no positive values came back as a 0-row
  tibble, and a year with a single country got `sigma = NA` from `sd()`, so an
  empty or blank convergence series was indistinguishable from a real one. Both
  now warn (`countryatlas_no_positive`, `countryatlas_thin_year`), the latter
  naming the years affected. An ordinary panel is unchanged and silent.
* **`gini()` and `theil()` returned `NA` without saying why.** Both carried a
  comment stating the package convention -- "NA plus a word about why (as for
  zero weights)" -- while the line beneath returned `NA` in silence for exactly
  those cases. An all-zero column and all-zero weights were indistinguishable
  from a missing input. Both now warn (`countryatlas_undefined_index`) naming
  which it was. Perfect equality still returns `0`, silently, because that is
  a value and not an undefined one.
* **A constant column made the spatial statistics return `NaN` in silence.**
  `morans_i()`, `gearys_c()`, `local_morans()` and `getis_ord()` all divide by
  the cross-sectional variance, so a column with no variation between countries
  is 0/0 -- and `getis_ord()`'s z-score came back `Inf` where the numerator was
  non-zero. For a statistic that is worse than an error, because it reads like
  a computed result. All four now warn
  (`countryatlas_zero_variance`), explaining that these measures compare
  variation between neighbours and there is none, and return `NA` rather than
  `NaN`. An all-zero column also stops `getis_ord()` dividing `gi_star` by its
  own zero sum. Real data is unaffected.
* **`map_provenance()` gained `n_total`.** `n_countries` holds the countries
  actually drawn *with a value* -- the numerator -- but the name reads like the
  map's country total, which is `n_countries + n_missing`. Anyone taking it as
  the denominator understated their own coverage. The denominator is now a
  field of its own, and the three counts are spelled out in `?map_provenance`.
* **The coverage caption did not pluralise.** `footnote = "auto"` is built
  with `sprintf()` and lands on a published map, where a single-country frame
  read `All 1 countries shown.` and an empty one `All 0 countries shown.` The
  same noun appears in `coverage_map()`'s caption and `map_provenance()`'s
  print block. All three now agree with the count, an empty frame says
  `No countries to show.`, and a frame with no coverage to report gets no
  caption rather than one full of `NA`.
* **`spatial_lag()` gave every year of a panel the first year's neighbour
  average.** It is the one spatial verb that returns a column aligned to the
  caller's own rows, and it matched on `iso3c` alone. France's
  `gdp_per_capita` ran 39,683 -> 158,734 -> 277,784 across three years while
  `gdp_per_capita_lag` sat at 63,409 for all of them, so `value / lag` --
  the Moran-scatterplot axis this column exists for -- silently compared 2002
  against 2000. A panel now gets a lag computed per year; a cross-section is
  unchanged.
* **The spatial statistics silently computed on an arbitrary year of a
  panel.** `align_weights()` -- shared by `morans_i()`, `gearys_c()`,
  `getis_ord()`, `local_morans()`, `spatial_lag()` and `lisa_map()` -- reduced
  to one row per country with a bare `distinct(iso3c, .keep_all = TRUE)`, so a
  panel collapsed to whichever row came first in the frame. Moran's I on the
  same data returned 0.47 or 0.29 depending only on row order, and unlike the
  map verbs these said nothing at all about having chosen. They now go through
  the shared reduction: the earliest year, deterministically, with the
  `countryatlas_panel` warning. A genuine cross-section is unaffected.
* **"Only the earliest year of each country is used" was not true.** The
  one-row-per-country reduction behind `rate_check()`, `audit_coverage()`,
  `correlate_indicators()`, `world_table()` and every map verb warned that it
  keeps the earliest year, but the code was
  `distinct(iso3c, .keep_all = TRUE)`, which keeps whichever row comes *first
  in the frame*. That is the earliest year only for a caller who happened to
  sort by year: shuffle the same panel and `rate_check()` returned a different
  numerator for France (20 sorted, 30 shuffled) and the map verbs drew a
  different year, while the warning went on promising "earliest" either way.
  The earliest year is now selected explicitly, so these verbs are
  reproducible for a given frame regardless of row order, and the survivors
  keep their original relative order.
* **`standardize_country()` silently destroyed columns the caller never asked
  about.** `add` defaults to `c("iso3c", "iso2c", "continent", "region")`, so
  the ordinary call -- `standardize_country(d, country)`, to get `iso3c` --
  also replaced any `continent`, `region` or `iso2c` already in the frame. A
  user's own regional classification vanished without a word, while the eleven
  other column-adding verbs all report this through `warn_overwrite()`. It now
  warns (`countryatlas_unasked_overwrite`) naming the columns, *only* when
  `add` was left at its default: passing `add` yourself still means you asked
  for those columns, as documented. `add = "iso3c"` adds just the code.
* **`country_join()` silently multiplied rows when standardising collapsed two
  names onto one code.** `wdj_to_key()` maps distinct inputs to the same code --
  `"France"` and `"FRANCE "`, or `"Congo"` and `"Congo-Kinshasa"` -- so a `y`
  whose names all looked distinct could join one country twice. dplyr says
  nothing: with unique keys on the other side that is an ordinary one-to-many,
  not the many-to-many it flags. Two rows became three, France appeared twice
  with different values, and a downstream `sum()` double-counted it. Both
  `country_join()` and `country_join_all()` now warn
  (`countryatlas_key_collapse`), naming the code and the inputs that collapsed
  onto it. Only a *collapse* is reported: duplicates already present in the
  input under one name, and country-by-year panels, are legitimate one-to-many
  joins and stay silent. `warn = FALSE` silences it.
* **Subnational maps counted countries instead of regions, and binned on
  them too.** `na_coverage()`, `classification_table()`, `apply_binned_fill()`
  and `imputed_count()` de-duplicate before counting -- the polygon backend
  repeats a country's value down every vertex -- but keyed on `iso3c`. A
  subnational frame carries `iso3c` *as well as* a region code, so every NUTS
  region of a country collapsed to one row: a 280-region map reported
  "27 of 27"; because `distinct()` keeps the first row per key, blank regions
  inside a country whose first region had data were reported as **zero
  missing**, claiming complete coverage of a map with visible holes; and the
  quantile breaks were computed from 27 values rather than 280, so the colour
  scale itself was wrong. All four now key on the most specific unit column
  present (`nuts_id`, then `iso_3166_2`, then `iso3c`, then `group`).
* **`country_borders()` silently omits five whole countries at its default
  scale, and `country_factsheet()` reported the resulting short count as
  fact.** Adjacency comes from Natural Earth, and the default `scale = "small"`
  (110m) has no polygon at all for Andorra, Liechtenstein, Monaco, San Marino
  or the Vatican -- countries for which a land border is the entire geography.
  They contributed no rows, so each reported zero neighbours and France
  reported 8 instead of 10, under a heading stating the count as fact.
  `?country_borders` now has a *Which countries the default leaves out*
  section naming them and pointing at `scale = "medium"` (which has all five),
  and `country_factsheet()` names what its count excludes -- only for the
  countries actually affected. (The Brazil and Suriname borders it reports for
  France are real, via French Guiana.)
* **Passing something that is not a column to a column argument leaked a raw
  rlang error.** `quo_arg_name()` called `rlang::as_name()` directly, so
  `world_map(data, 5)` failed with `Can't convert a double vector to a string.`
  and `world_map(data, gdp_per_capita + 1)` -- a natural thing to try -- with
  `Can't convert a call to a string.` Neither named the argument, the function,
  or what was expected, and the leak reached every one of the package's ~66
  unquoted column arguments. The error now names the argument and the offending
  expression, and suggests the fix: compute the column first for an expression,
  drop the pronoun for `.data$x`, or pass a bare name or string for a literal.
* **`world_table(value = NULL)` labelled an unsorted slice with a `rank`
  column.** With nothing to rank on, the frame keeps whatever order it arrived
  in and `top_n` takes an arbitrary slice -- but the result was still numbered
  1..n under a heading that told the reader these were the top n by something.
  `world_table(world_snapshot$countries, top_n = 5)` presented Afghanistan as
  "rank 1" next to an empty GDP cell. The column is now added only when a
  `value` was given, and truncating an unsorted table warns.
* **A failed World Bank download was cached to disk as if it had succeeded.**
  `WDI::WDI()` answers a failed request by warning and returning a zero-row
  frame; memoise cached that, and the World Bank cache is persistent -- so one
  call made while the network was down poisoned every later session until
  someone ran `clear_wdi_cache(disk = TRUE)` by hand. An empty response is now
  never cached, and says why (`countryatlas_no_data`).
* **`register_country_source(cache = )` did nothing.** The flag was stored in
  the registry and reported by `country_sources()`, but nothing ever read it:
  the documented per-session memoisation never happened, and `cache = FALSE`
  was equally inert. Results are now memoised per source, keyed on the
  indicator, countries, years and any extra arguments, and cleared by
  `clear_country_cache(source = )`. Empty results are not memoised.
* **`world_map(engine = "tmap")` could not draw in its default style.**
  `tm_scale_intervals()` is tmap's *interval* scale, and `"cont"`/`"cat"` are
  not interval styles -- they name different constructors. So the default
  `style = "continuous"` failed outright with tmap's `Invalid style. Style
  should be one of "fixed", "sd", "equal", "pretty", ...`, and
  `style = "categorical"` warned that an interval scale was being applied to
  non-numeric data. Each style now reaches the constructor tmap has for it.
* **`flow_map()` drew every trans-Pacific flow across the whole map.** A great
  circle Tokyo -> Los Angeles has longitudes running `...178, 179, -179,
  -178...`, and `geom_path()` under `coord_quickmap()` joined those two points
  literally, so the arc streaked back across Africa instead of crossing the
  ocean. Arcs are now split at the antimeridian and land exactly on the edge.
* **`flow_map()` titled its legends `weight`** whatever the caller's weight
  column was called, because the internal arc frame's column is literally named
  `weight`. Both scales now carry the real name -- which also merges what were
  two legends of the same variable into one.
* **`geom_country_labels(mapping = )` could only name four columns, and
  cancelled `flag = TRUE`.** The centroid reduction returned
  `iso3c`/`long`/`lat`/`flag` and dropped the rest, so
  `aes(colour = continent)` -- the ordinary reason to pass a mapping -- died on
  "object 'continent' not found". Separately, the caller's mapping *replaced*
  the defaults instead of adding to them, so supplying one removed the `label`
  aesthetic entirely and silently ignored `flag`.
* **`animate_world(title = )` was discarded.** The frame marker was written
  straight into `title`, overwriting anything passed through `...` to
  `world_map()`. The title now stays and the frame label moves to the subtitle.
* **`style = "binned"` ignored `n_bins`.** It was passed to ggplot2 as
  `n.breaks`, which is only a hint -- `scales::extended_breaks()` snaps to round
  numbers -- so `n_bins = 5`, `6` and `7` all drew five bins and `3` drew four.
  `world_map()`, `globe_map()` and `value_by_alpha_map()` now compute explicit
  equal-interval boundaries, so `n_bins` means the same thing under `"binned"`,
  `"quantile"` and `"jenks"` as documented -- and in every verb that takes it,
  not just `world_map()`. `globe_map()` and `value_by_alpha_map()` also record
  the boundaries in provenance, which only `world_map()` did before.
* **`classification_report = TRUE` fabricated classes for continuous fills.**
  With no break vector the report fell back to one row per distinct *value*: a
  continuous choropleth of GDP per capita produced a 189-row table of `n = 1`
  that looked like a classification and described nothing. A continuous
  colourbar now reports `NULL` and warns (`countryatlas_no_classes`); `"binned"`
  gets a real table, because it now has real breaks.
* **`bubble_map()` and `spike_map()` failed on data already carrying
  `centroid_lon`/`centroid_lat`** -- including `world_geometry("centroids")`'s
  own output. dplyr suffixed both sides of the join to `.x`/`.y` and the `aes()`
  referring to `centroid_lon` then found no such column. The incoming columns
  are dropped in favour of the bundled ones.
* **`bubble_map()` and `spike_map()` overstated their coverage.** Both join the
  bundled centroid table, which does not cover every code in the codelist. The
  five countries with snapshot data and no centroid -- Hong Kong, Macao,
  Gibraltar, the British Virgin Islands and Tuvalu -- were dropped at draw time
  (`bubble_map()` left-joined and let ggplot2 mutter "Removed 5 rows";
  `spike_map()` inner-joined and said nothing), but provenance was computed on
  the frame as it arrived. A population map that never drew Hong Kong reported
  "215 of 215" with `n_missing = 0`. Coverage is now measured against what is
  actually placed, and a new `countryatlas_no_centroid` warning names the
  countries that could not be.
* **`na_style = "hatched"` and `disputes = "mark"` silently discarded the
  projection.** `ggpattern::geom_sf_pattern()` and the `geom_sf()` inside the
  dispute layer each return `list(<layer>, <CoordSf>)` -- a default
  `coord_sf(crs = NULL)` -- and ggplot2 replaces the plot's coordinate system
  unconditionally when a coord is added. Both layers go on after
  `wdj_coord_sf()`, so they threw away the requested CRS and its latitude clip:
  `world_map(projection = "mercator", na_style = "hatched")` and the same call
  with `projection = "robinson"` drew byte-identical maps. Two honesty features
  quietly reprojecting the map is the opposite of the point.
* **`clear_wdi_cache(disk = FALSE)` deleted the on-disk cache, and any other
  file beside it.** memoise's `cache_filesystem()$reset()` is
  `file.remove(list.files(dir, full.names = TRUE))`, so `forget()` on a
  disk-backed memo was never an in-memory operation -- the call the examples
  label "forget the in-session memo" wiped the persistent cache and every
  unrelated file that happened to share the directory. The `disk` flag gated
  nothing on the way in; it only decided whether the directory was additionally
  removed. Dropping the memo reference is what an in-session clear means here,
  and the next fetch reads the existing entries straight back.
* **`years` meant something different for the World Bank than for every other
  source.** It is documented as a numeric year *vector*, and the four adapters
  honour that, but the WDI path used only `min()`/`max()` as a request range and
  never filtered the result -- so `years = c(2000, 2020)` asked for two years
  and got twenty-one.
* **A mistyped `classify` silently added no classification columns.**
  `world_data()` and `country_data()` filtered the argument with `intersect()`,
  so `classify = "incomes"` matched nothing and quietly produced a frame with no
  income, continent or region column rather than saying the value was not
  recognised. `language` went straight to WDI, where a length-2 value surfaced
  as "the condition has length > 1". Both are now checked before the network
  call, so the error does not depend on having a connection.
* **A mistyped `region` drew an empty map in silence.** `region` accepts a
  continent, a group name, `iso3c` codes, country names or a bounding box, and
  anything matching none of those fell through to name-matching, resolved to
  `NA`, and produced an empty subset -- so `region = "Europ"` returned a blank
  map with no explanation, and `region = NA` reached the internal tests as base
  R's "missing value where TRUE/FALSE needed". Both are now reported. An
  explicitly-uppercase unknown code still yields an empty subset, which is
  deliberate and documented in the code.
* **`add` reported its problems under somebody else's argument.**
  `standardize_country(add = )` and `locate_country(add = )` name attributes to
  derive from `iso3c`, and neither validated the argument: an unknown name
  surfaced as countrycode's complaint about its `destination` argument, a bad
  one in `locate_country()` as `convert_country()`'s `to`, and `add = NA` as
  base R's bare "missing value where TRUE/FALSE needed". Both now check it, and
  the shortcut table they accept is shared with the validator so the two cannot
  drift apart.
* **A malformed `custom_match` could put a non-code in `iso3c`.** `origin` was
  validated and the override table was not, although every value in it lands in
  the `iso3c` column -- and the `iso3c` branch whitelists those values as valid
  by construction, so nothing downstream rejected them either.
  `custom_match = c(Freedonia = 1)` therefore produced `iso3c == "1"`, and every
  join, geometry lookup and group test after it keyed on that. The table must
  now be the name-to-code map `country_overrides()` returns.
* **`wdi_search()` searched for whatever it was given.** Only `field` was
  checked, so a non-string `pattern` went straight into the regex and matched
  something plausible: `wdi_search(1)` returned 10,125 indicators and
  `wdi_search(NA)` the entire 29,495-row catalogue, both without complaint,
  while an empty one leaked base R's "invalid 'pattern' argument". A `cache`
  that was not a `WDIcache()` object died on "$ operator is invalid for atomic
  vectors". Both are now checked.
* **`spin_globe(file = )` was the one argument its validation block missed**,
  so a non-string path leaked base R's "invalid 'path' argument" from inside the
  writer -- the block's own comment says a bad argument is the caller's bug and
  the message should not depend on which optional packages are installed.
* **`audit_coverage()`'s group breakdown measured one indicator and did not
  say which.** `by_group$na_rate` is computed on the first indicator -- with the
  default that is whichever numeric column comes first -- while the printed
  heading reads "Coverage by group", so a region's GDP coverage of 0.25 read as
  its overall coverage even though population and life expectancy were complete.
  The table now carries an `indicator` column naming what was measured.
* **`compare_sources()` could report two providers as agreeing perfectly when
  it had never compared them.** An unnamed `indicator` of more than one code was
  silently truncated to its first element and broadcast to every source, so the
  verb compared a code against itself and found no disagreement. Its own error
  message elsewhere already told callers to "pass a single unnamed code";
  nothing enforced it. Now rejected, with a pointer to the named form.
* **`deflate()` overwrote an existing column in silence.** `to_ppp()` and
  `smooth_rates()` are the same shape -- take a panel, write one derived column
  back into it -- and both announce a clash before destroying the caller's
  column. `deflate()` did not, so a frame that already carried `gdp_real` lost
  it without a word.
* **A repeated country-year made `interpolate_missing()` rewrite observed
  values.** `stats::approx()` collapses tied x-values to their mean, so two rows
  sharing a year were both overwritten with the average -- 20 and 999 became
  509.5 apiece -- and the `_imputed` flag reported `FALSE` for them, since it
  compares "was `NA`" against "is not `NA`" and neither ever was. The safeguard
  the code documents, that a filler changing an observed value shows up as a
  flagged cell, cannot catch this case. The malformed input is now reported, and
  `approx()`'s own tie notice -- which reached the caller as an uninformative
  "There was 1 warning in `dplyr::mutate()`" -- no longer leaks.
* **A repeated country-year corrupted every verb that reads across rows.**
  `lag_by_country()`, `diff_by_country()`, `growth_rate()`, `index_to()`,
  `complete_years()`, `deflate()`, `to_ppp()`, `convergence_club()` and
  `beta_convergence()` all read neighbouring rows, so a duplicated
  country-year silently shifted them: with France's 2019 present twice as 20
  and 999, 2020 was lagged against 999, giving a difference of 979 and 4895%
  growth. The malformed input is now reported, and it names the offending key.
* **The one-row-per-country verbs collapsed a panel silently.**
  `world_table()`, `rate_check()`, `audit_coverage()`, `gridded_cartogram()`,
  `bubble_map()`, `spike_map()`, `globe_map()`, `interactive_map()`,
  `tile_map()` and `correlate_indicators()` reduce to one row per country -- which is for repeated *geometry* rows, not for time.
  Handed a panel they kept whichever row sorted first and presented that year as
  the answer: France's 2018 value of 10, out of 10, 20 and 30. They now say so.
  `tile_map()` was worse than silent -- its grid holds exactly one cell per
  country, so a panel fanned 239 cells out into 659 overlapping ones.
* **A panel handed to `world_map()` was drawn silently.** `attach_geometry()`
  joins a panel deliberately -- `facet_map()` and `animate_world()` are built on
  it -- so a multi-year frame reaching a single static map drew each country
  once per year and let whichever row came last win, with a caption that still
  counted each country once, so nothing looked wrong. `world_map()` now says so
  and points at the two verbs meant for a panel. Faceting *by* year and
  `animate_world()` resolve the panel and stay quiet; faceting by anything else
  does not -- each panel still stacks every year -- so there it still warns.
* **Three counts lacked the upper bound their coercion needs.**
  `world_query(n_bins = )`, `od_map(origins = )` and
  `convergence_club(min_size = )` validated only a lower bound, then coerced
  with `as.integer()` -- which past 2^31-1 returns `NA` with R's bare "NAs
  introduced by coercion to integer range". The query came out reading
  `BIN fill INTO NA`, `od_map()` reached `seq_len(NA)`, and every size
  comparison in `convergence_club()` became `NA`. `compute_breaks()` has carried
  this bound since 2.0.0; these three now do too.
* **`subnational_map()` dropped unmatched regions in silence.** Its join keeps
  the geometry and discards data rows that match none of it, so codes from a
  different NUTS vintage simply vanished -- and only a *total* join failure was
  reported, even though that error names the vintage problem exactly. Partial
  mismatches are now named too.
* **`check_country_match()` suggested a country for a blank cell.** The guard
  skipped `NA` and `""` but not `"  "`, and Jaro-Winkler finds spurious
  similarity between a two-space string and a name containing spaces -- so a
  whitespace-only cell, the commonest thing a CSV import produces, came back
  confidently suggesting "Congo - Kinshasa" at a distance of 0.29, well inside
  the threshold.
* `audit_coverage()`'s `n_missing` and `na_rate` are no longer named vectors.
  `vapply()` names its result after `indicator`, so `a$na_rates$na_rate` handed
  back `c(gdp = 0.1)` instead of `0.1` -- the same wart `country_network()`
  already calls `unname()` on.
* **Three verbs folded every uncoded country into a single row.** The
  de-duplication that stops a polygon frame counting a country once per vertex
  ran `distinct()` on `iso3c`, and `distinct()` treats `NA` as a value -- so
  countries the codelist could not resolve collapsed together.
  `audit_coverage()`, the verb the package points at for "which countries are
  missing", named one unmatched country out of four and divided every `na_rate`
  by a short `n`; `rate_check()` and `world_table()` quietly returned three rows
  for a five-row input. Coded rows are still collapsed; uncoded ones now
  de-duplicate on whatever else identifies them.
* **`country_join()` and `country_join_all()` never reported a failed
  reconciliation.** Reconciling both sides to a common key before joining is
  the entire premise of these two verbs, yet a name that resolved to no country
  was dropped in silence -- `join_world()` has warned about this all along, and
  `wdj_to_key()` only speaks up when a name resolves to `iso3c` but has no
  COW/GW code, which on the default `key = "iso3c"` is never. Both now name the
  unresolved values, per side and per table, and both take `warn = FALSE` to
  opt out.
* **`aggregate_regions(fun = "weighted_mean")` returned `NaN` for a zero total
  weight.** The unweighted branch turns an empty group into `NA` precisely
  because `0`, `NaN` and `+/-Inf` all read as real figures for a region there is
  no data for; the weighted branch checked only for missing values, so weights
  that were all zero -- or that cancelled -- divided by zero and leaked the
  `NaN` the documentation promises never to produce.
* **`add_indicator()` suffixed the column it said it was overwriting.** When
  the fetched indicator shared a name with a column already in `data`, the
  warning read "Overwriting ... rename them first to keep the original values"
  while the `left_join` underneath produced `val.x` and `val.y` -- so the caller
  got neither the column they asked for nor the one they had, advised by a
  message describing a mechanism that was not running. It now overwrites, as
  every other `warn_overwrite()` caller does.
* **An uncoded geometry row was counted as a country.** The bundled `sf`
  basemap carries one row with no `iso3c`; coverage counted it, so it sat in
  the denominator and in `n_missing` while `missing_iso3c` -- which sorts, and
  so drops `NA` -- listed one fewer. `footnote = "auto"` read "159 of 176
  countries shown; 17 missing" where provenance could name only 16 of them.
  Coverage now counts coded countries only, and the two agree.
* **`gridded_cartogram()` did the same, and mentioned only half of it.** It
  drops countries with no positive value and countries with no bundled
  centroid; only the second was ever reported, and provenance counted the
  survivors, so a grid covering 94 of 215 countries reported "94 of 94". It now
  names both drops and keeps the whole input as the denominator.
* **A cartogram reported the world it kept, not the one it started from.**
  `cartogram_map()` and `dorling_map()` drop every country without a positive
  weight -- necessarily, since a cartogram's area *is* the weight -- but they
  did it silently, and provenance was then computed on the survivors, so
  `n_total` shrank to match. A map showing 69 of 175 countries reported
  "69 of 73". Coverage is now measured against the frame as it arrived, and the
  countries that could not be sized are named.
* **`bivariate_map()` overstated its coverage the same way.** It classifies two
  variables jointly, so a country holding only one is drawn as no-data -- but
  provenance counted the x column alone. On a half-covered second variable it
  reported 159 countries shown where 69 were coloured. It now counts both, and
  names what it dropped.
* **A VSUP map overstated its own coverage.** `world_map(uncertainty = )`
  colours a country only where it has *both* a value and an uncertainty, but
  coverage was counted from missing fill values alone. On a frame whose
  uncertainty column was sparser than its value column -- an uncertainty join
  that half missed, say -- `footnote = "auto"` reported 159 of 175 countries
  shown when 69 were actually drawn, and `map_provenance()` agreed with it. The
  footnote that exists to stop a map overstating what it covers was doing
  exactly that. Coverage now counts both columns, and the countries dropped for
  a missing uncertainty are named.
* **`interpolate_missing()` flagged the wrong rows as imputed.** The
  "was missing" vectors were captured from the input and compared against the
  output, but the pipeline between them arranges by `iso3c` and `year` -- so the
  two lined up only when the caller happened to pass an already-sorted frame.
  On anything else the `_imputed` flags landed on entirely different rows,
  marking observed values as imputed and imputed ones as observed. Since
  `world_map()` reads that column to write its caption, an unsorted panel
  produced a map that misreported exactly which countries had been filled in.
  The flags now travel with their rows.
* **`flow_matrix(fill = )` corrupted the flows it was meant to leave alone.**
  `fill` is documented as the value for pairs with *no* flow, but the matrix was
  initialised to it and the observed weights accumulated on top, so `fill = -1`
  turned a flow of 10 into 9 -- and `symmetric = TRUE` then added the fill to
  itself. Flows are now accumulated into zero and `fill` is applied only to
  pairs no flow ever reached. The default `fill = 0` is unaffected.
* **`compare_sources()` reported disagreement between the wrong sources.** Every
  column of the pairwise summary is computed for its own pair except
  `n_disagree`, which read the row-wise spread across *all* sources: comparing
  three providers, a pair that agreed exactly was still counted as disagreeing
  wherever some third provider was the outlier. A source that reports one value
  for every country also leaked `cor()`'s "standard deviation is zero" warning;
  the correlation is `NA` either way, so the case is now decided explicitly.
* **`fetch_comtrade()` fetched only the first indicator.** It read
  `indicator[[1]]` and ignored the rest, so a two-commodity call quietly
  returned one column -- against the documented "one column per indicator" that
  its three sibling adapters honour. It now makes one request per commodity and
  joins them.
* **The source adapters validate `indicator` before doing anything else.**
  Called directly with an empty vector, `fetch_owid()`, `fetch_eurostat()` and
  `fetch_oecd()` returned a silent `NULL`, and `fetch_comtrade()` leaked
  comtradr's "subscript out of bounds". All four now give the same message
  `fetch_indicator()` always gave, and give it whether or not the provider's
  client package is installed.
* **A provider that changes shape is named as such.** `adapter_reshape()`
  checked the entity column but not the value column, although `fetch_eurostat()`
  hard-codes `"values"` and `fetch_oecd()` guesses between two spellings; a
  missing one became `as.numeric(NULL)` and surfaced as a recycling error
  several frames away. `fetch_comtrade()`'s year column had the same gap.
* **`country_sources()` no longer writes to your home directory.** It reported
  which of the five backing packages were installed by calling
  `requireNamespace()` on each, which *loads* them -- and `comtradr` creates
  `~/.cache/R/comtradr` in its `.onLoad`. Merely asking which sources were
  available therefore created a directory in the user's file space, which CRAN
  policy forbids and `R CMD check` reports as a new file in another directory.
  Availability is now tested with `system.file()`, which does not load.

Five defects found by auditing 2.0.1; three produced a wrong or unusable
picture rather than an error.

* **`cartogram_map()`, `dorling_map()` and `tile_map()` rejected a categorical
  `fill`.** All three hard-wired `scale_fill_viridis_c()`, so a discrete fill
  column -- which their `fill` argument documents no restriction on -- was
  accepted at the call and then died at *print* time with ggplot2's bare
  "Discrete value supplied to a continuous scale". The scale is now chosen from
  the column's type, as `world_map()` has done since 2.0.0.
* **`geom_country_labels(data = ...)` was unusable**: `data` was hard-wired in
  the layer call while `...` was documented as passing to that same call, so the
  ordinary idiom for labelling a subset failed on R's `formal argument "data"
  matched by multiple actual arguments`.
* **`world_map(projection = "mercator")` produced an unusable map.** Natural
  Earth's Antarctica reaches -90 degrees, where Mercator's *y* goes to infinity;
  PROJ clamps rather than erroring, so the panel came out three times taller
  than the world is wide, with the inhabited world a sliver above one grey
  rectangle of smeared Antarctica. Mercator is now clipped to +/-85.05113
  degrees, as Web Mercator has been since it was defined.
* **`locate_country(points = )` leaked an sf internal** ("no applicable method
  for 'st_transform'") for anything that was not already `sf`. A plain lon/lat
  frame is the commonest thing to pass, so it now gets a named error saying how
  to convert it.
* **`morans_i()` could not reveal what it had dropped** -- see below.
* **A wrong coding scheme died inside `countrycode`.** `origin` is user-facing
  on seventeen exported functions -- `neighbors()`, `country_join()`,
  `standardize_country()`, `flow_map()`, `country_timeline()`, `in_group()` and
  the rest -- and was validated only as "a string". Anything else reached
  `countrycode::countrycode()` and failed there, so `origin = "country"` raised
  a forty-item list of accepted values attributed to an argument the caller had
  never passed. Invalid schemes now raise a `countryatlas` error naming the one
  they probably meant: `"country"` and `"name"` both suggest `"country.name"`,
  `"iso3"` and `"ISO3C"` suggest `"iso3c"`.
* **`convert_country()`'s own `from` and `to` were the two that guard missed.**
  Every scheme other than `"country.name"` and `"iso3c"` skips the `iso3c` hop,
  so `from` reaches `countrycode()` directly and was still blamed on `origin`;
  and `to` was never checked at all, so a typo produced "the `destination`
  argument must be ... one of the column names in the conversion directory" --
  an argument, and a directory, the caller never mentioned. Both now name
  themselves and suggest the nearest real value, so `to = "contnent"` offers
  `"continent"`. The shortcut destinations (`flag`, `currency`, `tld`,
  `calling_code`, `name_fr`-style localised names) are unaffected.
* **`register_country_source(key_col = )` was used as a coding scheme.**
  `key_col` names the column `fetch` returns, and is documented and indexed as
  such -- but it was also handed to `countrycode()` as `origin`, so the only
  registrations that worked were those whose column happened to be named after
  a scheme. Every bundled source uses the `"iso3c"` default, which
  short-circuits before `countrycode()` is reached, so nothing in the package
  exercised it and the first source registered with `key_col = "country"` died.
  How to *read* the column is now its own argument, `key_type` (default
  `"iso3c"`), validated at registration and reported by `country_sources()`.
* **"5 countries ... has no cowc code."** The COW / Gleditsch-Ward key
  warning interpolates which table it refers to *between* the count and the
  verb, and cli keys an agreement marker to the most recent interpolated
  value -- a length-1 string here -- so the verb stayed singular however many
  countries were lost. `cli::qty()` now re-keys it to the count. (Only
  literal markup such as `{.field iso3c}` is safe to sit between a count and
  its agreement.)
* **`world_map(engine = "tmap")` ignored most of its arguments.** The engine
  received all of `world_map()`'s arguments and used ten of them, dropping the
  rest in silence: `projection` and `recenter` (so the documented default,
  Equal Earth, was dropped just as quietly as an explicit request), plus
  `na_style`, `footnote`, `classification_report`, `uncertainty` and
  `disputes`. `projection` and `recenter` are now honoured -- `wdj_crs()`
  resolves both and `tm_shape()` takes the result, which also means a bad
  projection name is finally rejected instead of ignored. The remainder are
  genuinely ggplot2-specific, so they are now named
  (`countryatlas_engine_ignored`) rather than quietly not happening.
* **`globe_map(interactive = TRUE)` accepted styling it could not use, and
  validated nothing.** The hand-off to MapLibre returned before
  `arg_match()` and `check_label_args()` ran, so `style = "nonsense"` and a
  length-3 `title` were taken without a murmur, and `style`, `palette`,
  `n_bins`, `borders`, `title`, `legend`, `na_label` and `backend` were all
  dropped. The arguments are now validated before the hand-off, and the ones
  MapLibre cannot carry are named.
* **`world_map(engine = "tmap")` ignored `na_label`.** The argument was
  passed into the tmap backend and never used, so a caller who named the
  missing-data key got tmap's own default instead, with nothing to indicate
  the label had been dropped -- while the ggplot2 engine honoured it. Every
  tmap scale takes `label.na`, so it is now passed through, and both engines
  share one normalisation of what the argument means (first element; a
  length-1 `NA` or `NULL` leaves the engine's own formatter alone).
* **`projection` was accepted and silently ignored by the polygon backend.**
  It is documented for the `sf` backend, and `recenter` already warned when it
  could not be honoured, but `projection` did not: the polygon backend returns
  unprojected longitude/latitude, so `projection = "mollweide"` looked
  honoured and changed nothing. It now warns
  (`countryatlas_projection_ignored`). `world_data(geometry = "none")` fetches
  no geometry at all and so warns for `scale`, `projection` and `recenter`
  alike, where before it took all three and dropped them.
* **`world_data(region = ..., geometry = "none")` returned every country in
  the world.** `region` is documented as a plain "Optional subset", but it was
  only ever applied inside `attach_geometry()` -- which the `"none"` branch
  skips -- so the argument was dropped in silence and a request for one
  continent came back with all of them. It now subsets the table directly. A
  bounding-box `region` has nothing to clip against without geometry, so that
  combination is refused rather than guessed at.
* **A `scale` of more than one value produced an error from base R.** The
  sf backend builds its cache key with `paste0("scale_", scale)` *before*
  validating, so a length-2 value vectorised into a two-element key and `[[`
  on an environment failed with "wrong arguments for subsetting an
  environment" -- naming neither the argument nor the package. A typo, a
  number, `NA` and `NULL` all reached the real check and reported properly;
  only the multi-value case escaped it. `scale` is now checked before it
  becomes a key. Affects `country_borders()`, `neighbors()`, `morans_i()`,
  `world_geometry(geometry = "sf")` and everything else routed through
  `get_world_sf()`.
* **`scale` was accepted and silently ignored by the polygon backend.**
  It selects a Natural Earth resolution, which only the sf backend fetches;
  the bundled polygons come at one resolution. `world_geometry(scale =
  "large")` and `attach_geometry(scale = "large")` therefore returned small
  polygons as though the request had been honoured, and `scale = 2` was not
  even rejected. Both now warn (`countryatlas_scale_ignored`) and point at
  `geometry = "sf"`, matching the existing notice for `recenter`.
* **`cartogram_diagnostics()` leaked the geometry engine's error.** One
  invalid ring makes s2 refuse `st_area()` with "Loop 0 is not valid: Edge 0
  crosses edge 2", which names neither the country nor the package. It now
  reports which geometries are invalid and points at `sf::st_make_valid()`.
  Unlike `country_borders()`, it cannot simply fall back to the planar GEOS
  engine: an area is the number this function reports, so switching engines
  would quietly change the answer.
* **`complete_years()` gave every year it invented an empty geometry.** The
  function exists so "animations do not flicker on missing years", but on an
  `sf` panel it produced exactly that: `tidyr::complete()` fills an invented
  row's geometry with an *empty* geometry rather than `NA`, so the
  `tidyr::fill()` that carries static columns forward saw nothing missing and
  skipped it, and the completed years rendered blank. Each country's own shape
  is now carried across its invented rows.
* **`complete_years()` also dropped the `sf` class.** `tidyr::complete()`
  returns a plain tibble while leaving the geometry column intact, so the
  result still held a live `sfc` column that `geom_sf()` and `st_bbox()` would
  not accept until the caller re-ran `st_as_sf()`. Fifteen other
  frame-returning verbs preserve `sf`; this one now does too.
* **`interactive_map()` discarded `...` for two of its five engines, one of
  them against its own documentation.** `@param ...` promised the dots reach
  `world_map()` for the `"plotly"` *and* `"ggiraph"` engines -- but the
  `"ggiraph"` branch assembles its own ggplot instead of calling
  `world_map()`, as a comment in it says, so
  `interactive_map(engine = "ggiraph", style = "quantile")` returned a default
  continuous map with no hint that the classification had been dropped. The
  `"leaflet"` engine builds its own map too and was not documented at all,
  and `"mapgl"` forwards to `mapgl::maplibre()`, which was also undocumented.
  Both self-assembling engines now name what they were given, the `@param`
  says where the dots actually go for each of the five, and `"plotly"` still
  forwards them (so an unknown argument is still an error there).
* **`world_table(engine = "tibble")` dropped `title` and `subtitle` in
  silence.** A tibble has no header, so neither can be drawn -- but the `gt`
  path already refuses to drop a subtitle quietly ("`subtitle` needs a
  `title`"), and the same objection applies here: the caller got back a table
  they believed was titled. Both are now named, and when `gt` is simply not
  installed the notice points at installing it rather than at an engine the
  session cannot reach.
* **`index_to()` with no `base_year` gave base R's error.** Omitting the
  argument reached `check_number()` and produced 'argument "base_year" is
  missing, with no default'. `deflate()`, the sibling with the same argument,
  has said "`base_year` is required." since 2.0.0.
* **`disputed_territories$administered_by` and `$claimed_by` mixed ISO codes
  with placeholders, and said nothing about it.** The columns read as `iso3c`
  and mostly are, but six parties are entities ISO assigns no code to and are
  written as `ABK`, `CYP-N`, `OST`, `PMR`, `SAH` and `SOL` -- so treating the
  column as ISO-keyed produced silent `NA`s in a package whose premise is that
  ISO codes are the join key. The `iso3c` column had always documented its own
  `NA` convention; these two now document theirs -- including that five of the
  six administer the like-named territory (which has no ISO code either) while
  `SAH` is a claimant only, of a territory ISO does code (`ESH`) -- and a test
  pins the exact set so it cannot drift or absorb a typo.
* **Three more character column arguments died on base R's "object not
  found".** `aggregate_regions(by = region)`, `world_table(columns = gdp)` and
  `country_codes(codes = iso3c)` all take column names as *strings* while
  sitting next to an argument that takes a bare column, which makes the slip
  an easy one -- and it failed while the argument was being evaluated, before
  any validation could run, so the message named neither the argument nor the
  package. `complete_years()`, `interpolate_missing()` and `audit_coverage()`
  already caught it; these three now do too. (`rank_countries(within = )`
  deliberately accepts either form and is unchanged.)
* **A repeated column name was ambiguous everywhere but one verb.** What
  `read.csv(check.names = FALSE)` gives you for a sheet with two `gdp` columns
  makes every by-name reference ambiguous. `interpolate_missing()` refused it;
  nothing else did. Ten verbs leaked the tibble error "Column name `gdp` must
  not be duplicated. Use `.name_repair` to specify repair" -- a message about
  internals in tibble, not about the caller's data -- and two, `per_capita()`
  and
  `to_ppp()`, silently succeeded: they computed from whichever column `[[`
  reached first and dropped the other without a word. The guard now lives in
  the validators every verb already calls (`check_cols()`,
  `check_panel_cols()`, `check_panel_unique()`), and in the two functions that
  reach `as_tibble()` before validating anything
  (`countryatlas_duplicate_columns`).
* **`rank_countries()` returned a `data.frame` where its siblings return a
  tibble.** It ended in `dplyr::ungroup()`, which strips a grouping but does
  not normalise a class -- and because it deliberately ungroups its input
  first, `mutate()` left a plain frame plain. Four sibling verbs ended the
  same way and were safe only because `group_by()` had already made their
  intermediate a tibble; all five now state the contract explicitly.
* **Four verbs leaked an incoming grouping.** `to_ppp()`, `smooth_rates()`,
  `interpolate_missing()` and `spatial_lag()` ended in a bare `data`, so they
  returned whatever class arrived: a grouped frame stayed grouped and the
  caller's next `mutate()` silently computed per group, and a plain
  `data.frame` never became a tibble. Their sibling verbs all normalise on the
  way out. The leak also hid on early-return paths of otherwise-fixed verbs --
  `smooth_rates(method = "none")`, `interpolate_missing(method = "none")` and
  both branches of `spatial_lag()` -- so a mode of the same function returned
  a different class from its default.
* **`join_world(region = ..., geometry = "none")` returned every row**, for
  exactly the reason `world_data()` did: the `"none"` branch returned before
  any of the geometry arguments were applied, though `region` is documented as
  a plain region subset. It now subsets, refuses a bounding box that has
  nothing to clip against, and warns for `scale`, `projection` and `recenter`.
* **`standardize_subnational()` never consulted the `regions` crosswalk, and
  did not say so.** It looks for a `geo_name`, `name` or `region_name` column
  in `regions::nuts_lau_2019` or `regions::all_valid_nuts_codes`. As of
  `regions` 0.1.8 the first exposes `lau_name_national` and `lau_name_latin`,
  and the second has no name column at all -- so neither matched, the lookup
  was skipped, and the caller was told only that their regions "did not
  resolve", with a hint about European coverage that had never been consulted.
  It now reports once per session that the installed `regions` offers no
  crosswalk it can use, so the real reason is visible. The behaviour is
  otherwise unchanged, deliberately: the `regions` datasets that *do* pair
  names with codes (`nuts_changes`, `google_nuts_matchtable`) key NUTS codes
  such as `DE2` rather than ISO 3166-2 codes such as `DE-BY`, and filling an
  `iso_3166_2` column from them would break this function's promise that an
  unresolved region gets `NA`, never a guess.
* **Four messages read wrongly when they described exactly one thing.**
  `subnational_map()` said "1 value ... match no geometry and are dropped",
  `check_dispute_coverage()` said "1 have no ISO code" and "1 ... territories
  appear", and `gridded_cartogram()` said "there are 1 countries to place".
  Each now agrees with its own count. `cli` keys a `{?...}` agreement to the
  most recent interpolated number, so the count and every agreement have to sit
  together -- an interpolation in between silently re-keys them, which is why
  the totals in two of these messages moved to the end of the sentence.
* **An unreachable GISCO reported itself as an `sf` method error.**
  `giscoR::gisco_get_nuts()` answers a failed download with `NULL` rather than
  an error -- the same shape as `owidR`'s blank result, which `fetch_owid()`
  names explicitly and for exactly this reason. `nuts_geometry()` had no such
  guard, so the `NULL` reached `sf` as "no applicable method for `st_as_sf`
  applied to an object of class NULL", which says nothing about GISCO being
  unreachable and sends the reader to check their arguments. An empty response
  now says so, naming the level and vintage. A response carrying no `NUTS_ID`
  column is diagnosed too: previously the derived `iso3c` came back
  zero-length and base R failed with "replacement has 0 rows, data has 2".
* **A changed World Bank response shape was reported as a failed download.**
  `countrycode()` is handed `raw$iso2c` directly to derive `iso3c`, so a
  response carrying neither key raised its own "sourcevar must be a character
  or numeric vector" -- which the fetch wrapper then relabelled "Could not
  fetch indicator … from the World Bank API". That blames the network for a
  change in the provider's response, and attaches advice about an argument the
  caller never passed. The response shape is now diagnosed by name, listing the
  columns that did arrive, and the wrapper passes that diagnosis through
  instead of overwriting it.
* **A non-numeric provider response became a column of `NA` in silence.**
  `as.numeric()` turns text that is not a number into `NA` without complaint,
  so a provider answering with `"n/a"` or `".."` -- or renaming a column so the
  value column now holds a label -- handed back pure `NA`. That reads as "the
  provider has no data for these countries", which is a very different claim
  from "the response was not numeric". `fetch_eurostat()` and `fetch_oecd()`
  were exposed because they name the value column outright, where
  `fetch_owid()` auto-detects it and so refuses a non-numeric column up front.
  The count is now reported, with the offending values shown. A value the
  provider itself reported as missing is already `NA` and is not counted.
* **The provider adapters discarded duplicate rows in silence.**
  `fetch_owid()`, `fetch_eurostat()`, `fetch_oecd()` and `fetch_comtrade()` all
  end by keeping one row per country-year, which is the contract the downstream
  joins rely on. But they kept whichever row came first and said nothing, so a
  provider answering with two different values for one country-year handed back
  an arbitrary one -- order-dependently, and invisibly. The count is now
  reported, as it is everywhere else this package drops rows. A genuine panel
  is untouched, and a clean response stays silent. `country_data()`'s own
  collapse is deliberately left quiet: there the cause is two `iso2c` codes
  mapping to one `iso3c`, which is structural to the World Bank country list
  and would fire on essentially every call.
* **A source whose keys collapsed repeated the caller's rows in silence.**
  Standardisation merges keys as well as failing on them -- "United States" and
  "USA" both reach `USA` -- and `add_indicator()`'s join then matched twice, so
  a two-row frame came back with three rows and one country holding two
  different values. dplyr only warns on many-to-many relationships, not
  one-to-many, so nothing was said. `join_world()` has warned about this since
  it gained that check; the source adapters now do too. The standardised key is
  also checked directly, because the collapse check by construction only sees a
  code reached from *more than one* raw value -- a source that simply returns
  `USA` twice collapses nothing and so said nothing, while the join still
  turned two rows into three. A genuine panel is untouched: the check keys on
  `iso3c` and `year` together wherever a year column exists. The documented
  fetch contract now states the uniqueness requirement, which it never did --
  it specified the columns and said missing data should arrive as `NA` rather
  than a missing row, but never that the key must not repeat.
* **A cross-section joined to a multi-year fetch lost the year that
  distinguished the rows.** Dropping the fetch's `year` column is right for a
  single-year fetch, where it broadcasts the one value across the frame. Done
  unconditionally, a two-row cross-section joined to a three-year source came
  back as six rows: the same `gdp` three times, against values whose year had
  just been deleted, so nothing recorded which year any of them belonged to.
  The column is now kept when it is doing work, and `add_indicator()` says why
  the frame grew.
* **`add_indicator()` handed back the source's own key column** as though it
  were requested data, because the columns to add excluded only `"iso3c"`. A
  source keyed on anything else left a stray column -- `country` next to
  `iso3c` -- in the result.
* **Re-registering a source kept serving the old one's answers.** The
  session cache keys on the indicator, countries and years but not on `fetch`,
  so correcting a broken adapter and registering it again returned the broken
  result -- which is what writing an adapter looks like. Registering a name now
  drops that source's cached answers.
* **An optional column argument was not validated like a required one.**
  `quo_arg_name()` gives every unquoted column argument its "must name a
  column, not `gdp + 1`" error, with the advice to compute the column with
  `mutate()` first -- and for the *required* arguments it did. Twelve
  optional ones called `rlang::as_name()` directly, so an expression reached
  the caller as rlang's own "Can't convert a call to a string", naming neither
  the argument nor what it wanted. In several functions the required argument
  was checked and the optional one beside it was not: `bubble_map()` validated
  `size` but not `color`, `flow_map()` validated `from` and `to` but not
  `weight`, `cartogram_map()` validated `weight` but not `fill`. Now covered:
  `per_capita(pop)`, `aggregate_regions(weight)`, `rank_countries(within)`,
  `flow_matrix(weight)`, `flow_map(weight)`, `bubble_map(color)`,
  `cartogram_map(fill)`, `gridded_cartogram(fill)`,
  `cartogram_diagnostics(weight)`, `interactive_map(tooltip)`,
  `animate_world(time)` and `join_world(country_col)`. `within`'s deliberate
  character-vector form is unaffected.
* **Three optional columns were never checked for existence either.**
  `per_capita(pop = )` left the population vector `NULL` and failed with base
  R's "replacement has 0 rows, data has 4"; `aggregate_regions(weight = )` and
  `rank_countries(within = )` failed from inside dplyr. All three now say which
  column is missing, as their required arguments already did.
* **A data frame was accepted where a country vector belongs.**
  `as.character()` on a data frame deparses each *column* into a string, so
  `neighbors(my_df)` came back with the two "countries" `c("USA", "FRA")` and
  `c(1, 2)` -- silently, because those are just strings that match nothing and
  every row then reads as "country not found". Nearly every other verb here
  takes `data` as its first argument, so handing a frame to one that takes a
  vector is the natural mistake, and eight of them took it:
  `neighbors()`, `convert_country()`, `country_timeline()`,
  `dissolve_country()`, `in_group()`, `distance_between()`,
  `check_country_match()` and `repair_country_names()`. `gini()` and `theil()`
  already refused a data frame; all of them now do. A data frame is only the
  common case -- `as.character()` deparses *any* list element that is not a
  single value, so `list(c("FRA", "DEU"))` collapsed to the one string
  `c("FRA", "DEU")` and returned a single `NA` where two codes were asked for.
  A flat list of scalars, a matrix and a factor all coerce correctly and are
  left alone.
* **`aggregate_regions()` crashed on the package's own `sf` output.** An `sf`
  frame is the one geometry shape this verb can aggregate correctly -- it
  carries a single row per country, so the totals are right -- but `dplyr`'s
  `sf`-aware `summarise()` unions the geometries per group, and the bundled
  Natural Earth polygons include two invalid ones (Sudan and Mozambique). So
  `join_world(geometry = "sf") |> aggregate_regions(population)` died with
  the raw GEOS error `TopologyException: side location conflict`, while the
  same call
  on a plain frame worked. It also drew the "aggregating counts each country
  once per geometry row" warning, which is true of a polygon frame and false of
  an `sf` one. The geometry is now dropped up front -- the documented return
  was always "a tibble of `by` plus the aggregated value" -- giving results
  identical to dropping it by hand, and the warning is confined to the polygon
  case where the hazard is real.
* **Four verbs reorder your rows and did not say so.** `growth_rate()`,
  `lag_by_country()`, `diff_by_country()` and `interpolate_missing()` read each
  country's series in time order, so they return rows sorted by `iso3c` then
  `year` -- but documented only "`data` with a column added". A caller holding
  a vector alongside `data` and relying on position would have had it silently
  stop lining up. The sorting is required and unchanged; the documentation now
  states it.
* **`?interpolate_missing` described the wrong mechanism.** It said the
  `"countryatlas_imputed"` attribute is what "the map verbs read". They do not:
  provenance counts the `*_imputed` *columns* by name, which is why the
  provenance chain survives verbs that drop attributes, as `dplyr` does. The
  page now points at the columns and says the attribute is a convenience
  nothing in the package consumes.
* **An `sf` frame stopped being `sf` halfway through a pipeline.**
  `per_capita()`, `share_of_world()` and `standardize_country()` all document
  their result as "`data` with the requested columns added", and
  `rank_countries()` honours that -- but these three ended with
  `tibble::as_tibble()`, which strips the `sf` class. The geometry column
  survived, so nothing looked wrong until the next verb:
  `join_world(geometry = "sf") |> share_of_world(population) |> world_map()`
  died on "`data` has no map geometry", while the same pipeline through
  `rank_countries()` worked -- which is what gave it away. `sf` now survives
  all three. Every other class is still normalised to a tibble and grouping is
  still dropped, both of which `as_tibble()` had been doing at the same time
  and only one of which was wrong.
* **Three map verbs broke on a frame that already had the columns they join
  in.** Each attaches coordinates under a fixed name, and when the caller's
  frame already carried that name dplyr suffixed both sides to `.x`/`.y`,
  leaving the code reading the unsuffixed name to fail on a column that had
  been renamed out from under it -- always as an internal `vctrs` or `ggplot2`
  error that says nothing about countries:
  * `gridded_cartogram()` on a frame carrying `centroid_lon`/`centroid_lat`
    -- which `country_meta` supplies, so joining it for capitals or area
    first is ordinary -- failed with "Can't subset rows with
    `is.na(df$centroid_lon) | ...`".
  * `tile_map()` on a frame with a `row` or `col` column, names common enough
    to collide by accident, failed with "Problem while computing aesthetics".
  * `flow_map()` on a frame with `x0`, `y0`, `x1` or `y1` -- exactly what a
    caller who geocoded their own endpoints has -- failed with "Can't subset
    columns that don't exist".

  `bubble_map()` and `spike_map()` already dropped the caller's centroid
  columns before the same join; all three now drop the colliding copy, and the
  output is identical either way. Where the clashing column is one the verb
  actually reads -- a `fill` that is also a tile coordinate, a `weight` that is
  also an arc endpoint -- it is refused by name rather than silently dropped.
* **`deflate()` and `to_ppp()` did not guard the join collision `per_capita()`
  does.** All three fetch a series into a `.wdj_*` column and join it on
  `iso3c`/`year`. A caller whose own frame already had that column made dplyr
  suffix both sides to `.x`/`.y`, leaving the fetched column unreachable and
  the arithmetic operating on nothing. `per_capita()` has dropped the colliding
  column since it hit this; its two siblings now do the same.
* **`audit_coverage()` reported perfect coverage of nothing.**
  `tibble::as_tibble()` turns a bare vector into a one-column tibble called
  `value`, so a character vector of country codes -- the mirror of the mistake
  above -- came back as a coverage object whose three tables were all empty.
  That reads as "no missing data" when nothing had been examined at all.
  `standardize_country()` already refused a non-frame; this now does too.
* **`world_table()` returned an empty table without saying why.** Rows whose
  value is `NA` cannot be ranked, so they are dropped -- but when that removed
  every row, a frame that went in with countries in it came back with none, and
  nothing distinguished "the column is empty" from "there was nothing to
  report". It now says so, while a partial drop (the normal case) and a 0-row
  input stay silent.
* **`recenter` was silently dropped on the polygon backend.** The polygon
  backend returns lon/lat vertices, and recentring them means re-splitting
  every ring at the new antimeridian -- which is what
  `sf::st_break_antimeridian()` does on the `sf` backend. `recenter` was simply
  ignored on the polygon side, so `join_world(recenter = 150)`,
  `attach_geometry(recenter = 150)` and `world_geometry(recenter = 150)`
  returned byte-identical coordinates to `recenter = NULL` and drew an
  Atlantic-centred map for someone who had asked for a Pacific-centred one.
  They now say so and point at `geometry = "sf"`, in the same shape as the
  existing bounding-box warning on that backend. `?world_geometry` was also
  the one help page that did not already describe `recenter` as an `sf`
  option.
* **`n_perm = 0` returned undocumented `NA` p-values.** `morans_i()` documents
  the escape hatch ("use `0` to skip the test"), and all three statistics
  validate `n_perm` with a lower bound of zero -- but `local_morans()` and
  `gearys_c()` described the argument only as "permutations for the
  pseudo-p-value", so passing `0` handed back a whole column of `NA` with
  nothing to say the test had been skipped. All three now document it, and say
  that `p_value` comes back `NA`.
* **Two bundled datasets did not name every column they have.**
  `?country_meta` listed sixteen of its seventeen columns, omitting `income` --
  the World Bank income group that `audit_coverage(by = "income")` and
  `rank_countries(within = "income")` read -- and `?world_snapshot` called
  `continent`, `region` and `income` merely "classifications" without naming
  them.
* **`interpolate_missing()` silently renamed a duplicated column.**
  `complete_years()` and `audit_coverage()` reject a frame with two columns of
  the same name; this one filled the first and handed the second back renamed
  -- `v` and `v` in, `v` and `v.1` out, without a word.
* **`index_to()` indexed a whole country to `NA` depending on row order.**
  `year == base_year` is `NA` for a missing year, and `x[c(NA, TRUE)]` returns
  an `NA` element *before* the real match, so taking the first element picked
  up the `NA`. The same three observations gave 100/150/50 with the missing
  year last and `NA`/`NA`/`NA` with it first. The base year is now chosen from
  the rows that have one.
* **`compare_sources()` invented a country from an unparseable year.**
  `read_year()` deliberately records `NA` for a time value it cannot parse, and
  subsetting a data frame by a condition containing `NA` appends a row of all
  `NA` -- a phantom country with no `iso3c`, which then survived the join into
  the comparison table.
* **A brace in borrowed text replaced the message it was reporting.** A `cli`
  bullet is a template, so text taken from somewhere else -- a parallel
  worker's error, an on-disk cache read failure, `countrycode`'s own complaint
  -- had its braces interpolated. A worker failing with `bad json {"a": 1}`
  reported "Could not evaluate cli `{}` expression" and the real failure was
  gone, which is the worst possible moment to lose it. Four sites now pass the
  borrowed text through as a value.
* **A bare column in a string-taking verb gave `object 'v' not found`.** Nine
  of these verbs take an unquoted column through tidy eval; three take strings
  -- `interpolate_missing(value)`, `complete_years(value)` and
  `audit_coverage(indicator)`. Writing the bare column that works everywhere
  else produced base R's "object not found", naming neither the argument nor
  the string it wanted. They now say what to write -- `value = "v"` -- while
  leaving a genuine error in the argument untouched.

## Spatial statistics: weights first

`morans_i()` shipped with one hard-wired weight scheme, land-border contiguity.
An island has no land border, so Japan, the United Kingdom, Australia,
Indonesia, Madagascar, New Zealand, the Philippines, Iceland and every small
island state carried no weight and left the analysis -- 49 of the 191 countries
with data in `world_snapshot`. The omission is systematic, not random.

* **`country_weights()`** builds the weights as a first-class object:
  `"contiguity"`, `"knn"` (every country gets neighbours, islands included),
  `"distance"`, or `"custom"` -- which is how a *non-geographic* neighbourhood,
  trade volume or migration flows, goes through the same API.
* **`morans_i(weights = )`** accepts it, and now reports `n_excluded` and an
  `excluded` list-column whatever the scheme. The two answers differ and both
  are defensible: contiguity gives I = 0.61 on 142 countries, k-nearest gives
  0.47 on 189.
* **`local_morans()`** and **`lisa_map()`** give the LISA cluster
  classification and its map; **`gearys_c()`**, **`getis_ord()`** and
  **`spatial_lag()`** complete the set. No `spdep` required -- at ~200 countries
  the dense arithmetic is trivial.

## Data sources beyond the World Bank

A contract, not N bespoke fetchers.

* **`register_country_source()`** teaches the package a new provider. A registry
  rather than more `Suggests`, so a source with no CRAN package -- V-Dem, the
  IMF, a proprietary internal feed -- is a first-class citizen without the
  package depending on anything.
* **`fetch_indicator()`**, **`add_indicator()`** and **`country_sources()`** are
  the user-facing verbs; **`fetch_owid()`**, **`fetch_eurostat()`**,
  **`fetch_oecd()`** and **`fetch_comtrade()`** ship as built-in adapters, each
  gated on its own client package.
* **`compare_sources()`** is the one that earns its place. Anyone can call
  `owidR`; what nobody does is tell you that OWID and the World Bank disagree
  about GDP per capita for fourteen countries because of different vintages, PPP
  bases or territorial definitions. On the ISO spine that comparison is one
  join.
* `clear_wdi_cache()` generalises to **`clear_country_cache(source = )`**; the
  old name still works.

## Time

* **`historical_geometry()`** draws the world as it was, from CShapes 2.0
  (1886-2019) -- states *and* colonies, which is what makes a pre-decolonisation
  map possible at all. `world_geometry(year = )` and `attach_geometry(year = )`
  route to it.
* **The ISO spine does not reach back, and the package now says so.** ISO 3166
  was published in 1974 and never covered colonies, so `country_join(key = )`
  and `country_join_all(key = )` gain `"cowc"`, `"cown"` and `"gwn"` as
  alternate spines, and warn -- naming which table -- about the dependencies
  COW/GW cannot carry. `historical_geometry()` is keyed on
  `gwcode`, with `iso3c` as a best-effort extra that is `NA` for every entity
  that never had one.
* **`country_groups_history`** (new dataset) dates membership for twelve groups,
  so **`country_groups(as_of = )`** and **`in_group(as_of = )`** answer the
  question a panel actually asks. The United Kingdom was in the EU in 2016 and
  not in 2021; EFTA had eight members in 1965 and has four now. Commonwealth,
  G20 and OPEC are deliberately *not* dated -- their histories involve
  suspensions and contested dates, and a fabricated date is worse than an absent
  one. The table is validated at build time against `country_groups_tbl`.
* **`country_timeline()`** reads the crosswalk both ways: what the USSR became,
  and what Estonia was part of. **`audit_time_coverage()`** catches the rows a
  successful join leaves wrong -- South Sudan with 1995 data, Czechoslovakia
  with 2001 data.

## Honesty as a feature

* **`world_map(na_style =)`** chooses how missing countries are drawn:
  `"grey"` (the default, and ambiguous -- grey reads as "low" to many people),
  `"hatched"` (diagonal hatching via the optional `ggpattern`, unmistakable and
  greyscale-safe), `"outline"` or `"omit"`.
* **`world_map(footnote = "auto")`** generates the coverage line -- "174 of 195
  countries shown; 21 missing" -- so a map cannot quietly overstate what it
  covers. A string is used verbatim.
* **`coverage_map()`** maps data availability itself, the cartographic
  counterpart to `audit_coverage()`'s table.
* **`world_map(classification_report = TRUE)`** attaches the breaks, the method
  and the count of countries per class to the plot. A map whose top class holds
  one country and whose bottom holds ninety is misleading, and the counts say so
  at once.
* **`classify_compare()`** draws the same choropleth under several
  classifications with that table for each. On `world_snapshot`'s GDP per
  capita, equal-interval and pretty breaks put 173 of 189 countries (92%) in a
  single class while quantile spreads them 38/38/37/38/38 -- the difference
  between a map that says something and one that says nothing.
  `?world_map` now states Brewer & Pickle's (2002) finding that quantiles read
  best and Jenks materially worse, with the citation, since that is the reverse
  of the common GIS default.
* **`value_by_alpha_map()`** encodes the value in colour and an equalising
  variable (usually population) in opacity, over a neutral background. It is the
  answer to the small-number problem -- an eleven-thousand-person country's rate
  shouting as loudly as a billion-person country's -- and unlike a cartogram it
  solves it without distorting geometry (Roth, Woodruff & Johnson 2010).

## Honesty, continued

* **`disputed_territories`** (new dataset) records *that* a territory is
  contested and *who the parties are*. It does not adjudicate, rank claims or
  imply any claim is better founded. **`dispute_policy()`** records which map
  convention you are using -- and warns that selecting `"de_jure"` does not
  change a single shape, because the package ships no claimed-boundary
  geometry. **`check_dispute_coverage()`** and `world_map(disputes = "mark")`
  stop a contested area passing unremarked.
* **`world_map(uncertainty = )`** switches the fill to a **value-suppressing
  uncertainty palette** (Correll, Moritz & Heer 2018): the value range contracts
  as uncertainty rises, so an uncertain estimate cannot claim an extreme colour,
  and the legend becomes the value x uncertainty grid.
* **`rate_check()`** flags rates computed over denominators too small to trust,
  and **`smooth_rates()`** shrinks them toward the global rate by
  empirical-Bayes. On a five-country example Tuvalu's rate shrinks from 2.7e-4
  to 5.9e-5 at a weight of 0.08, while China's is untouched at 0.9999.
* **`interpolate_missing()`** fills panel gaps and **flags every value it
  invents, non-optionally**. Gaps longer than `max_gap` are left alone, because
  interpolating across a decade is not interpolation. `world_map()` reads the
  flag and notes it in the caption.
* **`projection_distortion()`** measures what a projection does, numerically.
  It cross-validates: every equal-area projection reads exactly 1.000 areal
  distortion, Mercator reads 4.4 mean and 132 max, and Mercator alone reads
  ~0 degrees angular.

## Projections you can interrogate

* **`projection_info()`** returns the property table for all thirteen
  projections: construction family, equal-area, conformal, the PROJ string, and
  a note on what each is good for. `subset(projection_info(), equal_area)` is
  the short answer to "what may I safely use for a choropleth".
* **`projection_compare()`** draws one choropleth under several projections at
  once, holding the data and the classification fixed so only the CRS varies.
* **`tissot_map()`** draws Tissot's indicatrix -- circles of equal ground radius
  projected with everything else. On Mercator they stay round and grow
  enormously; on Equal Earth they hold their area and shear. It makes the
  package's honesty claim visible rather than asserted.
* Equal Earth is now documented as the recommended default for world thematic
  maps, with the Savric, Patterson & Jenny (2019) citation. The default itself
  is unchanged.

## Provenance

* **`map_provenance()`** reports what went into a map -- package version,
  snapshot year, geometry backend, projection, classification and its breaks,
  fill column, and countries shown versus missing. Every one of those is already
  known at plot time; this makes it readable. **Every** map verb records it, not
  just `world_map()`: a provenance feature that covers some of the verbs is
  worse than none, because the gap only shows up when someone relies on it.
* **`inst/CITATION`** credits the package *and* the sources it reconciles:
  `countrycode` (Arel-Bundock, Enevoldsen & Yetman 2018), the World Bank,
  Natural Earth, and the papers behind Equal Earth, the classification guidance,
  value-by-alpha and Moran's I. `citation("countryatlas")` now produces the full
  set.

## Flows, reporting and subnational

* **`flow_matrix()`**, **`country_network()`** and **`od_map()`** turn a
  bilateral table into a matrix, a network summary, or small multiples -- the
  answer to the arc map's problem, which is that past a few dozen flows
  `flow_map()` is a plate of spaghetti.
* **`country_factsheet()`** and **`world_table()`** are the last mile for the
  audience that wanted a table. `world_table()` uses `gt` when it is installed
  and a tibble otherwise.
* **`standardize_subnational()`**, **`nuts_geometry()`** and
  **`subnational_map()`** go one level below the country, scoped to where a
  maintained code system and free geometry both exist. There is no admin2, no
  bundled boundary data, and no attempt to pretend a French departement and a US
  state are the same kind of object.

## Cartograms, projections and renderers

* **`gridded_cartogram()`** allocates one cell per N people by largest
  remainder, so the reader can count. **`cartogram_diagnostics()`** reports the
  residual area error, because cartograms fail quietly -- on the bundled
  snapshot the default contiguous cartogram leaves Greenland 371x too large.
* `cartogram_map(type = "flow")` routes to `cartogramR`'s Gastner-Seguy-More
  algorithm. Each `type` now gates only on the package it actually needs.
* **`interactive_map(engine = "mapgl")`** renders through MapLibre GL, and
  **`globe_map(interactive = TRUE)`** turns the static orthographic globe into
  one you can spin with the mouse.
* **`world_map(engine = "tmap")`** is an alternative static renderer for people
  already working in tmap. The package stays ggplot2-native; this is a door, not
  a second front door.
* `world_query()` gains `layer`, `facet`, `size` and `n_bins`, so the
  database-side path can express bubbles, binning and small multiples.

## Deprecations

* **`wdj_overrides()`** now warns. It has been soft-deprecated since 2.0.0, but
  an interactive-only note never reaches the scripts still calling it. Use
  `country_overrides()`; the two return the same table.
* **`?wdj_overrides` now says it is deprecated.** The code started warning in
  this release, but the shared help page still described `wdj_overrides()` as
  "a backward-compatible alias" and its examples called it twice -- so the one
  place a reader goes to check was describing the previous release's behaviour,
  and running the documented examples emitted the deprecation warning. The
  examples now use `country_overrides()`.
* **`options(countryatlas.gdp_compat = TRUE)`** now warns. The
  `gdp_per_capita_2015` alias dates from 1.0.0 and will be removed.

## Other changes

* **The *Honest maps* vignette named two countries that contiguity weights do
  not drop.** Its island list included the United Kingdom and Indonesia, but the
  UK keeps its land border with Ireland and Indonesia keeps its borders with
  Malaysia, Papua New Guinea and Timor-Leste -- so neither is excluded. A
  vignette about maps quietly misleading, quietly misleading. Corrected, and it
  now uses the two as the illustration that you cannot tell from the finished
  map who dropped out.
* **Two more vignette claims corrected.** *Getting started* called
  `world_snapshot$countries$income` "an ordered factor"; it is a plain factor
  whose levels are in income order, built that way deliberately in `data-raw/`,
  and `is.ordered()` is `FALSE`. *countryatlas and ggsql* said `DRAW spatial`
  arrived at ggsql 0.4.0 while three places in `R/` said 0.4.1 -- both are true
  of different components, but read together they were a contradiction, so the
  engine and the R package are now named separately.
* Every vignette's prose claims are pinned by tests. Three were already; the
  four added or rewritten since then were not, which is how the errors above
  survived. The README's are pinned too, including that its verb table covers
  every non-deprecated export.
* `as_of` documents what a bare year means. It resolves to 1 January, so
  `in_group("Croatia", "EU", as_of = 2013)` is `FALSE` -- Croatia joined that
  July. The convention was always this; only the documentation was silent, and
  the examples all sat far from a boundary. Pass `"YYYY-MM-DD"` when the month
  matters.
* Every figure in the vignettes now carries alt text, so the pkgdown site and
  the rendered articles are readable with a screen reader.
* The `geom_country_labels()` example labelled all 188 countries at once, which
  made `ggrepel` drop every one of them; it now shows the two idioms that work
  -- selecting a subset through `data`, and zooming in.
* Documentation and vignettes zoom with `coord_quickmap()` rather than
  `coord_cartesian()`. Both replace the map's coordinate system, but only the
  former keeps the latitude-dependent aspect ratio, so the Europe inset was
  being drawn without any fixed aspect at all.
* `DESCRIPTION` declares `Language: en-GB`, and `inst/WORDLIST` records the
  package's technical vocabulary, so the CRAN spell check reports real typos
  instead of 300 false positives.

* `common_indicators` gains the two price-conversion series `deflate()` and
  `to_ppp()` reach for by default.
* `inst/CITATION` credits the new methods: Anselin, Geary, Getis-Ord, Correll et
  al., Phillips-Sul, Gastner-Seguy-More and Schvitz et al. alongside the
  existing set.
* The mean Earth radius is one shared constant rather than three literals.
* A bad `projection` or `scale` now says which argument it means. Both were
  validated by `match.arg()` inside a shared helper, which produces R's
  anonymous `'arg' should be one of ...` -- naming neither the argument nor the
  function the user called. Seventeen exported functions take `projection` and
  nine take `scale`, so one poor message was reachable a great many ways.
* `Suggests` grows to 41 packages. That is heavy, and it is the price of a light
  core: nothing here is needed to install the package or to draw a choropleth.

# countryatlas 2.0.1

A patch release. The only behaviour change is to a test and to where an optional
DuckDB connection keeps its state; nothing in the package's own API moves.

## CRAN check failures

* `test-standardize.R`'s de-accenting test failed on CRAN's two r-devel Fedora
  flavours, which run in a latin1 locale. The test asserted that outside a
  UTF-8 locale `iconv(x, to = "ASCII//TRANSLIT")` cannot produce a resolvable
  spelling -- generalising from `LC_CTYPE=C`, which is the case
  `?country_overrides` actually documents. That is not what glibc does: the
  `\u00e7` escape makes the input UTF-8 *marked* in every locale, so `iconv`
  reads it as UTF-8 and only the target charmap matters. Latin-1 has
  transliteration data and still yields `"Curacao"`; only `C`/POSIX, which has
  none, degrades to `NA` or `"Cura?ao"`. The test now asserts the invariant that
  holds in every locale -- de-accenting may or may not resolve, but it never
  resolves to a *different* country -- and passes under `C`, latin1, latin9 and
  UTF-8.

## Housekeeping

* `as_ggsql_source(format = "duckdb")` now opens its connection with
  `duckdb(shared_home = FALSE)` where the installed duckdb supports it (1.4 and
  later). By default duckdb keeps downloaded extensions and secrets in
  `~/.duckdb`, which a throwaway in-memory table has no business creating in the
  user's home; `R CMD check` also reports a new `~/.duckdb` among "new files in
  some other directories".
* The test suite no longer writes into the checking account's file space.
  Rendering one `girafe()` widget -- which `interactive_map(engine =
  "ggiraph")` does, and which no 1.0.0 test did -- makes `gdtools` copy 90
  Liberation font files into `tools::R_user_dir("gdtools", "data")`. `R CMD
  check` snapshots that tree and reports anything new, which is the NOTE CRAN
  raised against 1.0.0 for our own WDI cache (fixed separately, in
  `wdj_cache_dir()`). A new `tests/testthat/setup-user-dirs.R` points the R
  user directories at the session temp directory before any test runs, so the
  widget still renders, just somewhere disposable.
* `?clear_wdi_cache` claimed nothing was written until a World Bank fetch
  succeeded, so an offline session "never creates" the cache directory. The
  directory is in fact created the first time a *cached* fetch is attempted,
  because that is when the location has to be proved writable -- a failed
  fetch leaves it behind empty. The help page now describes what happens.

# countryatlas 2.0.0

A major release that wires countryatlas into the database-rendering world via
'ggsql', widens the map vocabulary, and fixes several correctness issues found
by auditing 1.0.0. The version is bumped to 2.0.0 because the bug fixes change
the output of `world_map()` (quantile binning), `bubble_map()` / `flow_map()`
(de-duplicated symbols), `geom_country_labels()` (label placement) and
`convert_country()` (override-only entities) — code that depended on the old
behaviour may see different maps or values.

## New: database-side rendering with ggsql

* `as_ggsql_source()` exports a curated, ISO-reconciled, WDI-joined table (with
  `sf` geometry WKB-encoded) as a [ggsql](https://ggsql.org) source — a DuckDB
  connection, a Parquet file, or a nanoarrow stream. countryatlas does the
  reconciliation ggsql's static bundled world can't; ggsql does the database
  push-down and Vega-Lite output countryatlas doesn't.
* `world_query()` emits a `ggsql` spatial query (`VISUALISE … DRAW spatial
  PROJECT TO … SCALE … LABEL …`) — a dependency-free string builder.
* `interactive_map(engine = "ggsql")` registers the data and renders the map in
  DuckDB, returning a Vega-Lite widget.
* `ggsql`, `duckdb`, `DBI` and `nanoarrow` are optional `Suggests`. See the new
  *countryatlas and ggsql* vignette.

## New: maps, projections and helpers

* `globe_map()` — an orthographic globe choropleth, with `backend = "sf"`
  (smoothest limb) or `backend = "polygon"` (needs only `maps` + `mapproj`).
* `spin_globe()` — a rotating-globe animated GIF (one `globe_map()` frame per
  central longitude, assembled with `gifski` or `magick`).
* `facet_map()` — small-multiple choropleths (the static counterpart to
  `animate_world()`).
* `wdj_crs()` gains eight projections (`mercator`, `winkel_tripel`, `eckert4`,
  `gall_peters`, `orthographic`, `azimuthal_equal_area`, `north_polar`,
  `south_polar`); `world_map()` / `world_geometry()` accept them all.
* `locate_country()` — point-in-polygon lookup tagging `lon`/`lat` with `iso3c`.
* `repair_country_names()` — the "act on it" companion to
  `check_country_match()`: auto-applies confident string-distance fixes.
* `country_join_all()` — reduce-join many messy country tables on the ISO spine.
* `growth_rate()`, `index_to()`, `share_of_world()` — panel analysis helpers.
* `country_overrides()` — preferred name for `wdj_overrides()` (kept as an
  alias) after the rename to countryatlas.
* `country_groups_tbl` gains `Mercosur`, `GCC`, `Nordic` and `Visegrad`.
* `country_borders()` — a tidy adjacency edge list built from polygon topology
  (`sf::st_touches()`), with `neighbors()` for a vectorised per-country lookup.
* `distance_between()` — great-circle (haversine) distance between two
  countries' centroids; needs neither `sf` nor the network.
* `dorling_map()` — the Dorling cartogram promoted to a first-class verb, with
  `k`/`itermax` tuning; `cartogram_map()` itself gains `...` passthrough to the
  underlying `cartogram::cartogram_*()` call.

## New: historical entities, inequality and spatial statistics

* `historical_codes` — a curated, dated crosswalk of dissolved entities
  (Soviet Union, Yugoslavia, Czechoslovakia, East Germany, Netherlands
  Antilles, North/South Yemen, pre-2011 Sudan, United Arab Republic,
  Tanganyika/Zanzibar, North/South Vietnam, Serbia and Montenegro) to their
  successor states, with retired ISO codes where they existed. Kosovo is
  included among the Yugoslav successors on a territory basis (documented).
* `dissolve_country()` — resolve a mixed vector of historical *and* modern
  names to successor `iso3c` rows (one-to-many, dated); modern names pass
  through as single rows, so a whole messy column pipes in unchanged.
* `check_country_match()` gains a `historical` column. It flags dissolved
  entities **even when countrycode "matches" them** — the headline case is
  `"USSR"`, which countrycode silently resolves to Russia's `RUS`, so
  Soviet-era data becomes Russian data with no warning.
* `correlate_indicators()` — pairwise indicator correlations on the spine
  (pearson/spearman, pairwise-complete, per-pair `n`), tidy long output.
* `beta_convergence()` / `sigma_convergence()` — the two standard convergence
  diagnostics: the growth-on-initial-level regression (with implied
  convergence speed and half-life) and per-year cross-country dispersion.
* `gini()` and `theil()` — inequality across countries, population-weightable;
  `theil()` decomposes exactly into between/within components when a grouping
  (continent, income) is supplied.
* `lag_by_country()` / `diff_by_country()` — panel lag and difference grouped
  by `iso3c` and ordered by `year`, completing the panel toolkit around
  `growth_rate()` / `index_to()` / `complete_years()`.
* `morans_i()` — global Moran's I with a permutation pseudo-p-value, computed
  on the row-standardised `country_borders()` adjacency. No `spdep`
  dependency: the weights come from the package's own curated topology.
* `spike_map()` — triangular spikes at country centroids (height ∝ value), the
  overplotting-resistant cousin of `bubble_map()`; needs only `maps`.
* `convert_country()` accepts `to = "name_<lang>"` (`"name_fr"`, `"name_es"`,
  `"name_zh"`, …) for localized country names via countrycode's CLDR tables.
* `world_map(style = "binned")` legends now show SI-formatted breaks
  (`4M`, not `4e+06`) when `scales` is installed; the continuous scale uses
  the same formatter.

## Bug fixes

* `bivariate_map()` errored on every call ("the condition has length > 1",
  pre-dating 2.0.0). The two fill columns were injected into
  `biscale::bi_class()` with `!!rlang::sym()`, but `bi_class()` reads them
  with `as.character(substitute(...))` rather than tidy eval, so the
  injection deparsed into a multi-element vector inside `biscale`. The
  happy path is now covered by a test (the old one only checked that the
  function errors cleanly when `sf` is *absent*).
* `as_ggsql_source()` and `interactive_map(engine = "ggsql")` errored on any
  `sf` input -- the whole point of the ggsql bridge. `sf::st_as_binary()`
  returns a classed `WKB` object, which `tibble` rejects ("all columns must
  be vectors"); the geometry column is now the plain list of raw vectors
  that `nanoarrow` encodes as binary and `DBI` writes as a `BLOB`.
* `projection = "winkel_tripel"` errored on every render -- one of the eight
  projections this release adds. The CRS built fine and the geometry
  projected fine, but `ggplot2::coord_sf()`'s graticule collapses to a
  degenerate single-point segment under PROJ's Winkel Tripel, which GEOS
  rejects ("point array must contain 0 or >1 elements"). The graticule is now
  skipped for that projection only; [theme_world_map()] blanks `panel.grid`
  anyway, so nothing visible changes. All 13 projections are now covered by a
  full-render test.
* `world_geometry("coastline", geometry = "sf")` errored with a GEOS
  `TopologyException` in every projection except `"plate_carree"`: a couple
  of Natural Earth rings are self-intersecting and `sf::st_union()` (unlike
  the spatial predicates) refuses them. The geometry is repaired before the
  union.
* `world_geometry(region = c(xmin, ymin, xmax, ymax))` -- and `world_data()`
  / `attach_geometry()` with a bounding-box `region` -- errored on the `sf`
  backend ("Loop 0 is not valid"), because `sf::st_crop()` runs under the
  strict S2 engine on unprojected geometry. It now clips with the GEOS
  planar predicate, as `country_borders()` / `locate_country()` already did.
* `convert_country()`'s `warn` argument was documented but silently ignored
  (every internal `countrycode()` call is wrapped in `suppressWarnings()`,
  because countrycode also warns on intermediate hops that
  `convert_country()` goes on to recover). It now reports inputs that match
  no country, like `standardize_country()` does. A recognised country whose
  destination value is genuinely missing still returns `NA` quietly.
* `world_map()` / `globe_map()`'s `na_label` was accepted and silently
  ignored. The `"quantile"`, `"jenks"` and `"categorical"` legends now label
  their missing-data key with it (the continuous and binned colourbars have
  no `NA` key to name, which the documentation now says).
* Kosovo's `XKX` resolves for `country` and `flag` from `from = "iso3c"`,
  not just from its name. It has no row at all in `countrycode::codelist`,
  so everything derived from the code was `NA` -- which surfaced as
  `country_borders()` / `neighbors()` returning `NA` names for Kosovo's four
  land borders, `locate_country(add = "country")` returning `NA` for points
  inside it, and `standardize_country(add = c("country", "flag"))` doing the
  same. The curated fallback table now carries the name and flag too.
* `per_capita()` without an explicit `pop` column died with an opaque
  `vctrs` error ("Can't subset columns that don't exist: `.wdj_pop`") when
  the World Bank population fetch failed or timed out -- `fetch_wdi()`
  deliberately degrades to a keys-only tibble in that case. It now reports
  the failed fetch and points at the `pop` argument.
* `theil()` returns `NA` shares (not `NaN`) for a perfectly equal
  distribution, where the total is `0` and the shares are undefined --
  matching how `gini()` and `share_of_world()` treat a zero denominator.
* `country_join()` / `country_join_all()` no longer cross-join rows whose
  `iso3c` is `NA`: unmatched countries used to collapse to a single `NA` key and
  fan out into a Cartesian product. The joins now pass `na_matches = "never"`
  (#4).
* `country_join_all()` validates the length of `origin` (must be 1 or one per
  table) instead of failing with a cryptic "missing value where TRUE/FALSE
  needed" error (#16).
* `join_world()`'s auto-detection (`detect_country_col()`) honours the candidate
  priority order instead of picking the first column by data-frame position, so
  a `region` column no longer shadows a real `country` column (#6).
* `standardize_country(add = ...)` accepts any raw `countrycode` destination
  (e.g. `"iso3n"`) again instead of erroring with "subscript out of bounds"
  (#5).
* `standardize_country(origin = "iso3c")` now validates codes: strings that are
  not real ISO 3166-1 alpha-3 codes become `NA` (and are flagged by `warn`)
  rather than passing through uppercased and unchecked (#12).
* `country_data(latest = TRUE)` / `world_data(latest = TRUE)` for a single year
  now returns each country's most recent non-`NA` value: the fetch window is
  widened so an earlier observation can actually be found (#7).
* `fetch_wdi()` keeps `iso2c` / `country` for a country that appears only in a
  non-first indicator (they are coalesced across indicators) instead of leaving
  them `NA` (#8).
* `world_map()` / `globe_map()` with `style = "quantile"` / `"jenks"` no longer
  error on a constant, single-country, or all-`NA` value column; degenerate
  breaks now fall back to a single bin (#9).
* `flow_map()` returns the base map (instead of erroring) when no
  origin-destination pair resolves to a centroid (#10).
* `aggregate_regions(fun = "min"/"max")` returns `NA` for an all-`NA` group
  instead of `Inf` / `-Inf` (#11).
* `share_of_world()` returns `NA` (not `NaN`/`Inf`) when the (per-year) total is
  zero or non-finite (#13).
* `gini()` returns `NA` with a warning for negative input rather than a value
  outside the documented `[0, 1]` range (#14).
* `spike_map()` no longer produces `NaN` spike coordinates when every height is
  zero (#15).
* `world_query()` honours `transform` even when `palette = NULL`, emitting a
  standalone `SCALE fill VIA <transform>` clause (#17).
* `world_map(style = "quantile"/"jenks")` computed breaks over polygon
  **vertices**, so a country's geometric complexity biased the quantiles and the
  bins held unequal numbers of countries. Breaks are now computed on one value
  per country.
* `bubble_map(backend = "sf")` placed bubbles in projected metres on a degrees
  base map (off the map). The base map and bubbles now share one projected CRS
  via `coord_sf()`.
* Polygon centroids returned more than one row for ten `iso3c` codes (overrides
  map several names — Azores/Madeira → PRT — to one code), fanning out joins in
  `bubble_map()` / `flow_map()`. Centroids are now one antimeridian-safe row per
  country (the largest piece).
* `geom_country_labels()` placed labels at the bounding-box midpoint over all of
  a country's pieces, so the US / Fiji / NZ labels drifted into the wrong ocean.
  Labels now sit on each country's largest piece.
* `projection = "plate_carree"` built an incoherent PROJ string
  (`+proj=longlat … +units=m`); it is now true equirectangular (`+proj=eqc`).
* `convert_country()` only applied `wdj_overrides()` for `to = "iso3c"`, so
  override-only entities (e.g. "Canary Islands", "Azores", "Bonaire") returned
  `NA` for every other destination (continent, region, iso2c, flag, currency,
  country name, ...). It now resolves the override-corrected `iso3c` first and
  derives every other destination from that.
* Kosovo's `XKX` needed extra care: it has no row at all in
  `countrycode::codelist`, so deriving destinations purely via the `iso3c`
  round-trip above is `NA` for everything — which would have *regressed*
  `flag`/`region`/`country`, since 1.0.0 already resolved those via direct
  name matching (verified against the actual 1.0.0 code). `convert_country()`
  now recovers from the original name when the `iso3c` round-trip comes back
  empty, and fills `iso2c`/`continent` (which neither path classifies) from
  the same curated fallback `standardize_country()` uses. Net effect versus
  1.0.0: zero regressions, plus newly-working `continent`/`iso2c` for Kosovo —
  which also fixes `locate_country(..., add = "continent")` for points inside
  it.
* `interactive_map(..., tooltip = )` was accepted but silently ignored by every
  engine (pre-dating 2.0.0). The `"ggiraph"` and `"leaflet"` engines now use the
  supplied `tooltip` column, defaulting to `fill` as before when omitted.
* `world_data(overrides = )` (and `attach_geometry(overrides = )`) accepted a
  custom name -> iso3c override set but silently ignored it (pre-dating 2.0.0) --
  the geometry backend always matched with the default `wdj_overrides()`. The
  override set now flows through to both the polygon and `sf` matchers, so a
  custom mapping actually changes which polygons a country claims.
* `repair_country_names()` no longer records a no-op "repair" when a dissolved
  entity's own name (e.g. "Yugoslavia", which exists in the codelist but has
  no ISO code) comes back as its closest suggestion; `dissolve_country()` is
  the right tool there and is what the report now points to.
* A mistyped column name is now reported by countryatlas rather than leaking
  out of `ggplot2` as a bare "object 'x' not found" from inside a layer, or out
  of `vctrs` as a subscript error. `world_map()`, `globe_map()`, `facet_map()`,
  `tile_map()`, `bubble_map()` (both `size` and `color`), `spike_map()`,
  `flow_map()` (`from`, `to` and `weight`), `interactive_map()` (`fill` and
  `tooltip`) and `morans_i()` all validate up front, matching the message
  `per_capita()` / `rank_countries()` / `bivariate_map()` already gave.
  `morans_i()` in particular used to blame the geometry ("not enough bordering
  countries with data") for a column that simply wasn't there.
* `audit_coverage(indicator = )` silently reported `n_missing = 0` and
  `na_rate = NaN` for a column name that isn't in `data`; it now errors.
* `world_map()` / `globe_map()` errored ("'length = 2' in coercion to
  'logical(1)'") when `na_label` was longer than one element. The first
  element is used to label the single `NA` key, and a `NULL` / `NA` label
  still leaves the default formatter alone.
* `per_capita()` sent `start = Inf` to the World Bank when `data` had a `year`
  column that was entirely `NA`; it now falls back to last year, as it already
  did for a frame with no `year` column at all. Its degraded-fetch guard also
  covers the join keys now, so a partial population fetch produces the
  actionable "pass a population column" error rather than a raw `vctrs`
  subscript error.
* `theil()` returned `NaN` when every weight was zero; it now returns `NA`,
  matching `gini()`.
* `world_map()` / `globe_map()` with `style = "categorical"` and a numeric
  `fill` column let `ggplot2` raise "Continuous value supplied to a discrete
  scale" at *build* time, naming neither the column nor the style. They now
  error at the call, name the column, and point at `"quantile"` / `"jenks"` /
  `"binned"`.
* `bivariate_map()` no longer leaks `biscale`'s "var has missing values,
  omitted in finding classes" warning, which fired on essentially every call
  because real indicators always have gaps (the classes were valid either
  way). Any other `biscale` warning still passes through.
* A `region` given as lowercase `iso3c` codes silently lost countries. Falling
  through to name matching resolved some codes by accident (countrycode's
  country-name regex is case-insensitive, so `"usa"` matched) but not others
  (`"can"` did not), so `region = c("usa", "can")` subset to the USA alone.
  Codes are now recognised in any case, matching what
  `standardize_country(origin = "iso3c")` already accepted; an all-uppercase
  unknown code is still taken at face value rather than reinterpreted as a
  country name.
* `country_codes()` silently dropped a column name it did not recognise, so a
  typo returned a table quietly missing that column; it now errors and lists
  the available shortcuts.
* Every `sf`-backed call printed three or more lines of `sf` internals to the
  console -- `"Spherical geometry (s2) switched off"`, `st_intersection`'s
  `"although coordinates are longitude/latitude ... assumes that they are
  planar"`, and the matching `"switched on"`. The source was
  `sf::st_break_antimeridian()`, which toggles the s2 engine and runs an
  intersection internally, and which sits on the path of *every* `sf` call: a
  plain `attach_geometry(geometry = "sf")` emitted them, as did `world_map()`,
  `world_geometry()`, `country_borders()`, `neighbors()`, `morans_i()`,
  `locate_country()` and `simplify_geometry()`. It is now wrapped in the same
  `quietly_sf()` helper the other `sf` calls already used, so those paths are
  silent. (The notices bypass R's condition system, so `suppressMessages()`
  could not have caught them.)
* `cartogram_map()` / `dorling_map()` never validated their `weight` or `fill`
  column, the one place the rest of the package's existence checks were missed.
  A bad `weight` reached `cartogram` as `"missing value where TRUE/FALSE
  needed"` (or, for the Dorling variant, a warning about `max()` and then a
  wrong picture), and a bad `fill` was not caught at all.
* `index_to()` likewise never checked its value column, so a typo produced a
  `dplyr` error from inside `mutate()`; `base_year` and `to` are validated too.
* Scalar arguments are validated, so a typo or an `NA` names the argument
  instead of surfacing as `"missing value where TRUE/FALSE needed"`, `classInt`'s
  `"n less than 2"`, or a `PROJ` complaint about `lat_0`. Covers `n_bins`
  (`world_map()` / `globe_map()`, on the binned path as well as the
  quantile/jenks one), `lon`/`lat`/`recenter`/`lat0` (`globe_map()` on **both**
  backends -- the polygon one goes to `coord_map()` and previously accepted a
  nonsense orientation silently), `n` (`flow_map()`), `max_height` / `width` /
  `alpha` (`spike_map()`), `max_size` / `alpha` (`bubble_map()`), `keep`
  (`simplify_geometry()`), `threshold` (`repair_country_names()`), `n_perm`
  (`morans_i()`), and `n_frames` / `fps` / `width` / `height` (`spin_globe()`).
* Two of those scalar arguments were not merely reported badly -- they drew the
  wrong thing in silence. A negative `max_height` drew `spike_map()`'s spikes
  upside down, and `globe_map(lat = )` beyond +/-90 built a CRS `PROJ` rejects,
  which only surfaced later as `coord_sf()`'s `"crs not found: is it missing?"`.
* `geom_country_labels(repel = TRUE)` silently drew plain labels when `ggrepel`
  was not installed -- the one degraded optional backend the package did not
  announce, where `classInt`, `gganimate` and `rmapshaper` all report theirs. It
  now says so once per session (the argument defaults to `TRUE`, so reporting on
  every call would be noise), and stays quiet when `repel = FALSE` was asked for.
* The number of bins no longer depends on whether `classInt` is installed. For a
  fractional `n_bins`, `classInt` truncated internally while the base-quantile
  fallback passed the fraction to `seq(length.out = )` and produced one break
  more, so the same call binned differently in different environments. `n_bins`
  is now truncated to a whole number of bins before either backend sees it.
* `simplify_geometry(keep = 0)` errored under `rmapshaper` but was silently
  accepted by the `sf::st_simplify()` fallback, so the same call behaved
  differently depending on which optional package the caller had installed. A
  proportion of zero keeps no vertices, and both paths now reject it.
* Count arguments are bounded above as well as below. The scalar checks
  required a finite number, but several call sites then coerce with
  `as.integer()`, which returns `NA` past `2^31-1` -- so `n_perm = 1e10` or
  `n_bins = 1e10` produced "NAs introduced by coercion" or, worse, "missing
  value where TRUE/FALSE needed". `n_bins`, `n` (`flow_map()`,
  `lag_by_country()`, `diff_by_country()`), `n_perm` and `n_frames` now name the
  range. `morans_i()` also dropped a `max(0L, ...)` clamp that the validation
  had made unreachable.
* `lag_by_country()` / `diff_by_country()` clamped `n <= 0` up to `1`, so a lag
  of `0` quietly returned a lag of `1`; it now errors.
* `complete_years(value = )` silently ignored a column name that wasn't in
  `data` under the default `method = "none"`, while erroring from `all_of()` for
  `"locf"` / `"linear"`; it now errors consistently.
* `interactive_map(engine = "ggsql")` now gates on `ggsql` >= 0.4.1 rather than
  mere presence. `DRAW spatial` -- the clause `world_query()` emits -- arrived
  in the ggsql *engine* at 0.4.0, while the ggsql R package is still 0.3.3,
  which accepted the call and then failed inside its own SQL front end on a
  clause it did not know. The gate now refuses with an actionable message
  instead. `?world_query` records that the clause has shipped in the engine but
  not yet in the R bindings, and that `PROJECT TO` additionally needs a spatial
  backend (for DuckDB, its `spatial` extension); `world_query()` itself remains
  a dependency-free string builder.
* `R CMD check` no longer writes to the checking user's persistent cache. The
  `\donttest{}` examples fetch from the World Bank, so the memoised on-disk
  cache was being populated under `tools::R_user_dir()` during a check; under
  check it now lives in the session temp directory instead. Normal use is
  unchanged, and `options(countryatlas.cache_dir = )` still overrides both.
  `?clear_wdi_cache` now documents where the cache lives and how to disable it.
* An unmatched country in your data could be drawn as a real country. dplyr
  joins default to `na_matches = "na"`, so an `NA` ISO code matched another
  `NA` ISO code -- and Natural Earth carries Somaliland as a polygon with no
  ISO code. Any row whose country failed to resolve therefore joined onto
  Somaliland's geometry and was plotted there; with two or more unmatched rows
  the join also fanned out many-to-many, duplicating that polygon once per
  row so the visible fill was whichever happened to be drawn last. Affected
  `attach_geometry(geometry = "sf")` (and so `join_world()` and `world_map()`
  downstream of it) and `bubble_map(backend = "sf")`. All country-keyed joins
  in the package now pass `na_matches = "never"`, which `country_join()` and
  `country_join_all()` already did; the keyless polygon is still drawn, now
  correctly as a no-data feature. A test asserts the invariant across the
  whole namespace so a new join cannot reintroduce it.
* `world_query()` emitted a silently malformed query for any argument that was
  not a single string. `sprintf()` vectorises, so `projection = c("a", "b")`
  produced two `PROJECT TO` clauses, `source = character(0)` deleted the `FROM`
  line entirely, and `title = NA` became the literal text `'NA'` -- each of
  which surfaced only later, as a parse error inside ggsql's SQL front end.
  `world_query()` and `as_ggsql_source()` now validate their string arguments
  up front and name the offending one. `NULL` still omits an optional clause,
  and an empty `title` is still allowed.
* `as_ggsql_source(format = "parquet")` built its `COPY ... TO '<path>'`
  statement by string interpolation, so a path containing an apostrophe --
  legal in a filename -- closed the SQL literal early and broke the statement.
  The path is now quoted with `DBI::dbQuoteString()`, matching the
  `dbQuoteIdentifier()` treatment the table name already had.
* `suffix = character(0)` made the whole computation vanish. `suffix` is
  `paste0()`-ed onto the value column's name, and dplyr's `"{character(0)}" :=`
  is a silent no-op -- so `growth_rate(x, g, suffix = character(0))` returned
  `x` unchanged, with no growth column and no error. `suffix = NA` produced a
  column named `gNA`, and `suffix = ""` overwrote the source column in place.
  `per_capita()`, `growth_rate()`, `index_to()`, `share_of_world()`,
  `lag_by_country()` and `diff_by_country()` now require a single non-empty
  string (`lag_by_country()`/`diff_by_country()` still accept `NULL` for the
  default suffix).
* Several arguments produced an error that named nothing rather than the
  argument at fault:
  * `convert_country(to = c("country", "continent"))` -- a plausible attempt at
    two destinations -- raised "the condition has length > 1", and a
    zero-length `to` or `from` raised "argument is of length zero".
  * `origin` did the same across every function that resolves country names.
    It is now validated once in the shared internal, so
    `standardize_country()`, `country_join()`, `country_join_all()`,
    `join_world()`, `flow_map()`, `neighbors()`, `distance_between()`,
    `in_group()`, `repair_country_names()` and `check_country_match()` are all
    covered.
  * `attach_geometry(by = character(0))` raised "argument is of length zero".
  * `aggregate_regions(by = character(0))` raised nothing at all: it grouped by
    no columns and silently collapsed the world into a single row. `by` remains
    documented as plural, so multiple grouping columns still work.
* Logical arguments are validated too, closing the same gap in two forms. The
  `borders` argument of `world_map()` and `globe_map()` fed a bare `if ()`, so
  a bad value raised one of four opaque base R errors ("missing value where
  TRUE/FALSE needed", "argument is of length zero", "the condition has length
  > 1", "argument is not interpretable as logical") -- none naming `borders`.
  Elsewhere the value went through `isTRUE()`, which never errors but silently
  turns anything that is not `TRUE` into `FALSE`, so the caller got the
  opposite of what they asked: `rank_countries(x, v, desc = "yes")` ranked
  ascending, putting the *lowest* value at rank 1, and
  `gini(x, na.rm = "yes")` kept the `NA`s and returned `NA`. All 23 logical
  arguments across the package now require `TRUE` or `FALSE` and name
  themselves when they do not get it.
* `gini()` and `theil()` returned a wrong number for a wrong-length `weights`
  vector. Both recycled it with `rep_len()`, which accepts any length
  silently, so `gini(1:10, weights = c(1, 2))` returned `0.2902` -- computed
  from an alternating 1,2 pattern -- where the correctly-weighted answer is
  `0.3`. Someone weighting by population and mistakenly passing a vector of
  the wrong length got a plausible figure and no indication anything was
  wrong. `weights` (and `theil()`'s `groups`) must now be length 1 or the
  length of `x`, and `weights` must be numeric. `complete_years()` likewise
  rejects a `years` vector that is non-numeric, empty, or contains `NA`, all
  of which it previously coerced to `NA` behind base R's warning.
* Omitting a required argument now names it. Every affected function resolved
  its column argument with `rlang::as_name()`, which raises
  `argument "x" is missing, with no default` for a missing value -- naming
  rlang's own parameter, and none of these functions has an argument called
  `x`. `world_map()`, `tile_map()`, `facet_map()`, `spike_map()`,
  `bubble_map()`, `globe_map()`, `interactive_map()`, `rank_countries()`,
  `growth_rate()`, `per_capita()`, `aggregate_regions()`, `index_to()`,
  `share_of_world()`, `lag_by_country()`, `diff_by_country()`,
  `beta_convergence()`, `sigma_convergence()`, `morans_i()`, `world_query()`,
  `country_join()`, `bivariate_map()`, `cartogram_map()` and `flow_map()` now
  report e.g. `` `fill` is required. `` Optional tidy-eval arguments are
  unaffected.
* `distance_between()` paired the wrong countries when `a` and `b` had
  mismatched lengths. It combined them through vectorised arithmetic, so R's
  recycling applied: 2 countries against 3 returned `a[1]`-`b[1]`,
  `a[2]`-`b[2]` and `a[1]`-`b[3]`, behind only base R's "longer object length
  is not a multiple" warning, and 2 against 4 recycled cleanly with no warning
  at all. Equal lengths, or a length-1 side for one-against-many, are now
  required -- the same rule `locate_country()` has always enforced for
  `lon`/`lat`.
* Three documented contracts did not match their code: `?locate_country` said
  `lon`/`lat` were "recycled together" when the function has always required
  equal lengths, and `?gini` / `?theil` promised that `weights` was "recycled
  against `x` the usual R way", which is precisely the behaviour removed
  above. All three now describe what the functions do. `locate_country()`'s
  length error also read "or an `points` sf object".
* Offline safety is now covered by tests rather than assumed. Checks run
  `\donttest{}` examples and rebuild vignettes, and CRAN policy does not allow
  either to fail for want of a network connection. `world_data()` and
  `country_data()` degrade a failed fetch to a warning and a metadata-only
  frame, and `wdi_search()` reads `WDI`'s bundled indicator list rather than
  the API; all three are now asserted, so a change that made any of them
  require a connection would break the suite.
* An unwritable cache directory silently cost you your data.
  `memoise::cache_filesystem()` does not validate the directory it is given: it
  constructs successfully and only fails when something is *written*, which
  happens deep inside the fetch. So with a read-only or otherwise unusable
  cache location, `country_data(cache = TRUE)` reported `Could not fetch
  indicator "..." from the World Bank API` and returned the country spine with
  every indicator `NA` -- blaming the API for a local permission problem, while
  the same call with `cache = FALSE` returned the data perfectly. (The
  `tryCatch()` that was meant to fall back never fired, because constructing
  the cache never errored.) The directory is now checked before use, with a
  fallback to session-only caching and a one-time message naming the real
  cause.
* Projected maps failed outright under `options(OutDec = ",")` -- the ordinary
  setting in comma-decimal locales. The PROJ strings are built by pasting
  numbers, so `recenter = 48.9` became `+lon_0=48,9`, which PROJ rejects; the
  invalid CRS then surfaced as sf's opaque "crs not found: is it missing?".
  Every number destined for a machine-readable string is now formatted with an
  explicit decimal mark.
* Two more of the same kind, triggered by `options(scipen = -10)`, which
  formats a *double* in scientific notation: `sf::st_crs(4326)` became
  `EPSG:4.326e+03` and yielded an `NA` CRS (surfacing later as
  `st_crs(x) == st_crs(y) is not TRUE` from `locate_country()`), and Natural
  Earth's scale `110` became `1.1e+02`, so `world_geometry(geometry = "sf")`
  failed with `'countries1.1e+02' is not an exported object`. Every EPSG code
  and Natural Earth scale is now an integer literal, which `scipen` does not
  affect.
* `simplify_geometry()` and `world_geometry("graticule")` are insulated from
  two upstream bugs of the same family, both reproducible without this package:
  `rmapshaper` serialises `keep` for V8, which rejects the `0,1` that
  `options(OutDec = ",")` produces, and `sf::st_graticule()` overflows the node
  stack under `options(scipen = -10)`. Both calls now run with those two
  options normalised, and the caller's settings are restored immediately
  afterwards.
* `rank_countries()` silently ranked within groups when handed a grouped frame.
  Its `mutate()` honoured the caller's `group_by()`, so the same data ranked
  `4, 1, 3, 2` ungrouped and `2, 1, 2, 1` after an incidental
  `group_by(region)` upstream in the pipe -- with `within = NULL` in both
  cases, which documents a global ranking. `rank`, `percentile` and `z_score`
  were all affected. `within` is now the only thing that sets the ranking
  scope, matching every other function here, which imposes its own grouping
  rather than inheriting the caller's. A test asserts that a grouped input
  changes no answer, and that nothing leaks grouping into its return value.
* A non-numeric value column now errors by name instead of producing nonsense.
  A factor column is easy to acquire -- `read.csv()` on a column with one stray
  non-numeric entry gives you one -- and arithmetic on it failed four different
  ways: `growth_rate()` and `per_capita()` returned a column of `NA`s behind
  base R's "'/' not meaningful for factors"; `share_of_world()`,
  `rank_countries()` and `aggregate_regions()` raised an opaque error from
  inside `dplyr::mutate()`; `gini()` managed "missing value where TRUE/FALSE
  needed"; and `morans_i()` quietly returned a plausible-looking statistic.
  These, plus `index_to()`, `diff_by_country()`, `beta_convergence()`,
  `sigma_convergence()` and `theil()`, now name the column and its actual type.
  `lag_by_country()` is deliberately unchanged: it does no arithmetic, so
  lagging a factor or character column remains legitimate.
* `aggregate_regions()` reported a figure for groups it had no data for. Values
  are dropped before aggregating, so a group whose every value is missing had
  nothing left -- and each base function got that wrong differently: `"sum"`
  returned `0`, `"mean"` and `"weighted_mean"` `NaN`, and `"min"`/`"max"`
  `-Inf`/`Inf` plus a warning. "This region's total is 0" is a claim, not an
  absence, which matters in a package built around honest missing-data
  handling. All six now return `NA`, as `"min"`/`"max"` were already meant to;
  groups that do have data are unaffected, and a partially-missing group still
  aggregates the values it has. `?aggregate_regions` documents this.
* `complete_years()` failed on a zero-row panel, where every other panel helper
  returns zero rows. With no `years` it reached
  `seq(min(numeric(0)), max(numeric(0)))` and died on base R's "'from' must be
  a finite number"; with `years` supplied it died on tidyr's "Can't recycle
  `year` (size 3) to size 0". Neither message names anything the caller did. It
  now returns the empty frame, columns intact, for all three `method` values --
  while still reporting a bad `years` or `value` argument.
* `bivariate_map()` and `cartogram_map()` (and so `dorling_map()`) failed
  inside their optional dependency when no row carried the values they need.
  This is easier to hit than it sounds: `attach_geometry()` joins
  geometry-on-the-left, so a frame with nothing in it arrives at the plotting
  verb as full-length columns of `NA`. `biscale` then indexed
  `sVar[1:(length(sVar) - 1)]`, which becomes `1:-1`, and reported "only 0's
  may be mixed with negative subscripts"; `cartogram` compared `NA` in
  `if (meanSizeError < maxSizeError)` and reported "missing value where
  TRUE/FALSE needed". Neither mentions the data. Both now say which columns are
  empty, as `spike_map()` already did, and both reject a non-numeric column by
  name. Partly-missing columns still draw from the rows that do have values.
* `gini()` could kill the R session. It computed the weighted mean absolute
  difference with `outer()`, an n-by-n matrix -- fine for the ~200 countries it
  is written for, but it is exported and accepts any numeric vector. A
  geometry-joined column is 99,338 rows, needing about 79 GB, and the process
  was killed outright: no error, no message, no result. The kernel is now the
  sorted cumulative form, O(n log n) in time and O(n) in memory, which agrees
  with the pairwise definition to floating-point noise (verified across ties,
  zero weights, single values and 340 random cases) and handles a million
  values in well under a second. Every documented figure is unchanged.
* `aggregate_regions()` silently multiplied its answer when given a frame with
  map geometry attached. The polygon backend expands each country into hundreds
  of vertex rows, so a row-wise total counts it once per vertex: for the bundled
  snapshot a regional total of 497,265 came out as 280,951,373. It is reachable
  directly off `world_data(geometry = "polygon")`. It cannot de-duplicate on
  `iso3c`, since `by = c("region", "year")` roll-ups legitimately repeat a
  country, so it now warns and says what to do instead. Country-level tables
  and panels are unaffected.
* `?audit_coverage` described the raw list it returns without mentioning that
  the object is classed and has a `print()` method, so what you actually see at
  the console is a formatted report rather than the list. Both are now
  documented.
* `world_geometry("ocean")` drew nothing at all, in every projection. Under the
  S2 engine -- sf's default since 1.0, so everywhere --
  `st_as_sfc(st_bbox(-180, -90, 180, 90))` collapses to a two-point, zero-area
  polygon, and the collapse is invisible because `st_bbox()` reports the stored
  extent instead of recomputing it from the (empty) coordinates. The rectangle
  is now built by constructing the ring explicitly, which S2 never gets to
  reinterpret, and its edges are densified so a curved projection has points
  to bend: the layer comes out at Earth's true surface area (5.1e14 m2) and
  covers 98-100% of the countries layer across all nine world projections.
  `st_break_antimeridian()` is no longer applied here at all -- with
  `lon_0 = 0` it cut the outline at +/-180, its own edges, taking it down to two
  thirds of the globe and, under Mollweide, to nothing.
* Where an ocean background cannot be drawn, `world_geometry()` now says so
  instead of returning an invisible layer: the four hemispheric projections
  (`"orthographic"`, `"azimuthal_equal_area"`, `"north_polar"`,
  `"south_polar"`) show half the globe, and a whole-globe rectangle cannot be
  recentred without covering only part of the map.
* `world_geometry("coastline")` and `world_geometry("ocean")` returned a bare
  `sfc` rather than the `sf` object `?world_geometry` promises (and that the
  other four `what` values deliver), so dplyr verbs failed on exactly those
  two. Both are now `sf`; the geometry is unchanged.
* `?world_geometry`'s `@return` was a single line naming no columns. It now
  lists what each `what` returns, and warns that the sf backend's
  `centroid_lon`/`centroid_lat` are in the object's own CRS -- projected metres,
  not degrees, so `centroid_lon` for France is `174097`, not `2.1`. Use
  `country_meta$centroid_lon` for degrees.
* `sf::st_coordinates()` failed on `world_geometry("countries", geometry =
  "sf")`, in every projection including the default. Natural Earth supplies 177
  uniform `MULTIPOLYGON`s, but `st_break_antimeridian()` runs an
  `st_intersection()` internally that collapses a single-part `MULTIPOLYGON` to
  a `POLYGON`, leaving 148 `POLYGON` + 29 `MULTIPOLYGON` -- an `sfc_GEOMETRY`
  column, which `st_coordinates()` does not support. Extracting vertices from
  the package's own geometry, an ordinary thing to want, therefore errored with
  "not implemented for objects of class sfc_GEOMETRY". The column is cast back
  to `MULTIPOLYGON`, which is a type change only: row count, codes and land
  area are unchanged. `?world_geometry` also now notes that a hemispheric
  projection returns empty geometries for the far side, where the same
  `st_coordinates()` limitation applies for a different and correct reason.
* `world_map()` accepted a frame with no geometry, returned a `ggplot` object
  without complaint, and then failed only when the plot was printed -- with
  ggplot2's "Problem while computing aesthetics ... Caused by error in
  `.data$long`", which names nothing the caller did. It validated the `fill`
  column but never the `long`/`lat`/`group` columns the polygon path needs.
  Forgetting `attach_geometry()` is the easiest mistake to make here, and it is
  easy precisely because the other plotting verbs do not need it:
  `tile_map()`, `bubble_map()`, `spike_map()` and `globe_map()` all take a
  country-level frame, so `world_map(snap, gdp)` looks like it should work too.
  It now says so at the call, and names the fix. `facet_map()` delegates to
  `world_map()` and is covered by the same check; the four country-level verbs
  are deliberately unchanged, and a test pins that asymmetry.
* `interactive_map(engine = "ggiraph")` reported a missing geometry differently
  from the other engines. It assembles its own `ggplot` rather than calling
  `world_map()`, so it bypassed that check and failed at render time on
  `.data$long`, while `engine = "plotly"` named the problem properly. Both now
  give the same message. `?interactive_map` also documents that the `"leaflet"`
  engine attaches geometry itself if handed a country-level table, which the
  others do not.
* The numeric fill styles now require a numeric column. `style = "continuous"`
  and `"binned"` reached ggplot2 and failed only when the plot was printed
  ("Discrete value supplied to a continuous scale", "Binned scales only support
  continuous data"), neither naming the column; `"quantile"` and `"jenks"` did
  not fail at all -- the break computation returns early on a non-numeric
  column, so the fill fell through to the discrete scale and drew a plausible
  map whose legend claimed quantile bins it had never computed. The reverse
  direction, `style = "categorical"` on a numeric column, was already guarded,
  so this closes the pair. `animate_world()` and `facet_map()` inherit it.
* `attach_geometry()` no longer warns when given a panel. Joining one row per
  country-year against polygon vertices is legitimately many-to-many -- it is
  what `animate_world()` and `facet_map()` are for -- so dplyr's "unexpected
  many-to-many relationship" warning was noise. The relationship is now
  declared, as the cache merge already did.
* `?repair_country_names` now says which way the `stringdist` fallback errs.
  The `threshold` argument already noted that the metric changes when
  `stringdist` is absent (Jaro-Winkler versus a length-normalised edit
  distance); it now adds that the fallback is the more conservative of the two,
  repairing a subset of what Jaro-Winkler would -- mainly missing transposed
  letters, as in "Frnace" -- and never choosing a different country. Measured
  over 120 single-typo names: 98 repaired with `stringdist`, 77 without, none
  repaired that `stringdist` did not, and no wrong repairs either way. A test
  now holds the package to that.
* `simplify_geometry()` undid the geometry-type fix above. Both simplifiers
  collapse a single-part `MULTIPOLYGON` to a `POLYGON`, so a homogeneous input
  came back as a mixed `sfc_GEOMETRY` column and `sf::st_coordinates()` failed
  on the result -- the same defect as `world_geometry("countries")`, restored
  one step downstream. The output is cast back; row count and geometry are
  unchanged.
* `simplify_geometry()`'s `keep` argument now means roughly the same thing with
  and without `rmapshaper`. The `sf::st_simplify()` fallback was given a fixed
  `dTolerance` of `(1 - keep) * 10000`, i.e. metres whatever the coordinate
  system: 9 km on a projected frame, which barely simplified anything (79% of
  vertices kept at `keep = 0.1`), and 9000 *degrees* on a lon/lat frame, which
  is meaningless and only survivable because `preserveTopology` keeps a husk.
  The tolerance is now scaled to the object's own extent, so the fallback
  behaves the same on either coordinate system and responds monotonically to
  `keep`. `?simplify_geometry` says that only `rmapshaper` honours `keep` as a
  true proportion.
* `gini()`'s negative-value warning said `Returning "NA"`, which reads as the
  two-character string rather than the missing value. It now renders as `NA`,
  matching the same correction already made elsewhere.
* The test suite no longer fails on R >= 4.6. Several tests set
  `options(scipen = -10)` to exercise the scientific-notation bugs fixed above,
  but R 4.6 clamps `scipen` to a minimum of -9 and warns ("invalid 'scipen'
  -10, used -9"), so an exact round-trip assertion failed and three warnings
  were raised -- an `ERROR` under `R CMD check` on current R, even though the
  package code itself was correct. The tests now use -9 and compare against the
  value R actually stored.
* The `wdj_overrides()` soft-deprecation notice told the wrong people. It lived
  in the shared function body, so in an interactive session it fired for
  `country_overrides()` -- the very replacement it recommends -- and for every
  public function that takes the override table as a default argument
  (`standardize_country()`, `convert_country()`, `attach_geometry()`,
  `check_country_match()`, `repair_country_names()`, `world_data()` and the
  geometry backends). Callers were advised to stop using a function they had
  never written, and the advice was unactionable. The notice now fires only for
  a direct call to `wdj_overrides()`; the table itself is unchanged. The
  documented default is now `country_overrides()`, so `?attach_geometry` and
  friends name a function the reader can actually look up.
* `?country_borders`'s whole-world example runs again. It was wrapped in
  `\dontrun{}` on the grounds that the whole-world adjacency is expensive, but
  it takes about a quarter of a second from a cold session -- only 2.7 times
  the `region = "Europe"` subset that already ran live. CRAN discourages
  `\dontrun{}` for code that can be executed, so it is now a guarded
  `\donttest{}` and is actually exercised by the check. That leaves six
  `\dontrun{}` topics, each genuinely unrunnable: a live World Bank fetch, an
  HTML widget, a DuckDB connection, a 60-frame GIF, and a call that deletes
  files.
* `?country_overrides`'s advice for accented names in a non-UTF-8 locale did
  not work in that locale. It offered de-accenting with
  `iconv(x, to = "ASCII//TRANSLIT")` as an alternative to running under UTF-8,
  but `//TRANSLIT` is itself locale-dependent: under `LC_CTYPE=C` it returns
  `NA`, or replaces each accent with `?` when given an explicit
  `from = "UTF-8"`, so nothing resolves either way. The section now says
  de-accenting has to happen while still in a UTF-8 locale, and that the ASCII
  spellings the override table carries are what work everywhere.
* A bad `options(countryatlas.workers)` reached `mclapply()`. The option is
  advertised in this file, so a stray value is reachable: `"abc"`, `NA` and
  `Inf` all became `NA` workers and surfaced as "missing value where
  TRUE/FALSE needed" from deep inside a parallel fetch, while `c(2, 4)`
  silently used the larger of the two. It is now checked, and the message names
  the option. Values below one are still clamped to one, as before -- that path
  was never the problem.
* A bad `options(countryatlas.cache_dir)` did the same thing one layer down.
  The option is documented in `?clear_wdi_cache`, and a stray value reached
  `dir.exists()`/`dir.create()`: `NA`, a number and `TRUE` each gave "invalid
  filename argument", `character(0)` gave "argument is of length zero", and a
  two-element vector gave "the condition has length > 1". It is now checked and
  the message names the option. An empty string is still accepted and still
  degrades to session-only caching; `NA_character_`, which used to degrade
  silently, now errors like the other bad values.
* An empty cache directory failed on R 4.6 but not on R 4.4. `dir.create("")`
  warns and returns `FALSE` on R 4.4, so the fallback to session-only caching
  worked; on R 4.6 it *errors* with "zero-length 'path' argument", which
  escaped the surrounding `suppressWarnings()` and propagated. An empty path is
  now recognised as "no disk cache" before the filesystem is touched, so the
  behaviour is the same on every R version.
* `?theil` now says that a row with a missing *group* is dropped along with rows
  whose value is missing, so the decomposition's `total` is computed over the
  grouped subset and can differ from the ungrouped `theil(x)`. On the bundled
  snapshot that difference is entirely Puerto Rico, which has no `region`.
  `theil()` also gains numeric anchors on the bundled data, which `gini()`
  already had.
* Every `sf`-backed verb leaked `sf`'s internal chatter as `message()`
  conditions. The console was already clean, but silencing it by redirecting the
  message *stream* leaves the conditions themselves travelling to whatever
  handler the caller installed, so `purrr::quietly()`, `testthat::expect_silent()`
  or a plain `withCallingHandlers()` around `attach_geometry()`, `neighbors()`,
  `country_borders()`, `locate_country()` or `morans_i()` still saw three to nine
  "Spherical geometry (s2) switched off" / "assumes that they are planar"
  notices. They are now muffled as well as redirected. (The comment claiming
  these notices bypass R's condition system was simply wrong -- they are
  ordinary `message()`s, and only a few GDAL diagnostics need the stream
  redirect.)
* `?world_geometry` called all four azimuthal projections "hemispheric" and said
  the far side comes back as empty geometries. That is true of `"orthographic"`
  alone; `"azimuthal_equal_area"`, `"north_polar"` and `"south_polar"` are
  Lambert equal-area and image the *whole* globe, with the far side stretched
  around the rim and nothing dropped. The page now distinguishes them and points
  at `region` for a genuine polar view, and the error `"ocean"` raises in those
  projections no longer gives "it shows one hemisphere" as the reason.
* `?world_geometry` now documents the Natural Earth features that have no ISO
  code and so come back with `iso3c` `NA` -- Somaliland at every scale, plus the
  Indian Ocean Territories and Ashmore and Cartier Islands from `"medium"` on.
* `?theme_world_map` said the theme is used by *all* the package's plotting
  functions. `bivariate_map()` is the exception -- it applies
  `biscale::bi_theme()` so the map matches biscale's own legend, and its axis
  titles, panel grid and background differ as a result. The page now names the
  exception.
* `?simplify_geometry` documented `keep` as a proportion "(0-1)", but `keep = 0`
  is rejected on both simplifier paths (it would leave nothing to draw). The
  range now reads "greater than 0 and at most 1".
* `complete_years(value = )` fabricated data in the columns it was *not* given.
  A numeric column left out of `value` was classified as a static attribute and
  carry-filled, so naming **fewer** columns invented **more** figures -- and even
  `method = "none"`, which exists to complete the grid and fill nothing, produced
  a carried-forward value for the missing year. Measure columns are now excluded
  from the attribute carry whether or not they are named; an unnamed one stays
  `NA` in the rows `complete()` adds. `value = NULL` behaves exactly as before.
* `aggregate_regions()` silently ignored `weight` for every `fun` except
  `"weighted_mean"`, returning the unweighted figure -- on European GDP per
  capita, 38,323 where the population-weighted answer is 29,896. Passing
  `weight` with any other `fun` now errors, mirroring the existing abort when
  `fun = "weighted_mean"` is given no weight.
* `flow_map()` dropped a flow whose endpoint it could not resolve without a
  word, and when nothing resolved it returned a bare world map with no arc
  layer at all. It now warns, naming the values it could not place and pointing
  at `origin` -- feeding it `iso3c` codes while `origin` still defaults to
  `"country.name"` is the usual cause, and it drew a blank map.
* `?in_group` now says that a value `origin` cannot resolve answers `FALSE`,
  indistinguishable from a country that is genuinely outside the group, and
  points at `check_country_match()` for telling the two apart.
* `world_map()` / `globe_map()` passed `palette`, `title`, `legend` and
  `na_label` to `viridisLite` and `ggplot2` unchecked, so a mistake came back in
  their vocabulary rather than the package's: `palette = c("magma", "viridis")`
  reached a bare `switch()` and reported "EXPR must be a length 1 vector", and a
  numeric `palette` was accepted without a word. A length-2 `title` or `legend`
  was accepted too, and `ggplot2` then drew both strings on top of each other.
  All four are now checked; `world_query()` already validated the two of them it
  takes (`palette` and `title`). `na_label` keeps its documented tolerance --
  there is one `NA` key, so the first element wins and a length-1 `NA` still
  means "leave the default formatter alone" -- but it now says so instead of
  doing it silently. A number is still a perfectly good *label*.
* `country_data()` / `world_data()` resolved a conflict between `latest` and the
  shape arguments silently, and with opposite precedence depending on the year:
  a multi-year `year` overrode `latest = TRUE`, while a single year had
  `latest = TRUE` override `panel = TRUE`. The winner is unchanged -- both were
  already the documented behaviour -- but the call now warns, naming the
  argument being dropped, instead of returning a shape nobody asked for.
* `locate_country(tolerance_km = )` was unvalidated, and a character value did
  not merely give an opaque message -- it produced a **wrong answer**. R compares
  `dkm <= tolerance_km` as strings when the tolerance is character, and
  `"2650" <= "a"` is `TRUE`, so every unmatched point snapped to its nearest
  country however far away it was: a mid-Pacific point came back as Fiji, where
  the documented behaviour is that open ocean stays `NA`. Now checked, before the
  `sf` gate.
* Three more scalars the validation sweep had missed now name themselves instead
  of failing in a dependency's vocabulary: `correlate_indicators(min_n = )` (an
  `NA` gave "missing value where TRUE/FALSE needed", a length-2 value "the
  condition has length > 1"), and `dorling_map(k = )` / `dorling_map(itermax = )`
  (which reported `cartogram`'s "all sizes are missing and/or non-positive" and
  an assertion naming its internal `maxiter`).
* `interactive_map(engine = "ggsql")` reported a missing `ggsql` >= 0.4.1 for a
  frame that simply had no geometry -- sending the caller after a package that
  has not shipped in the R bindings at all, only to meet the real error
  afterwards. The `sf` check now runs ahead of the package gates.
  `spin_globe()` had the same inversion for its `fill` column: its scalars were
  moved ahead of the animation gate in an earlier pass, but the column check was
  not, so a mistyped column still asked for `gifski`.
* `join_world()` could not read a column of ISO codes without being told to.
  Its fallback detector tried each character column with
  `origin = "country.name"`, which does not match most alpha-3 codes, so a
  column of them was rejected outright -- and a column *named* `iso3c` was found
  by name but still read as country names, so
  `join_world(tibble(iso3c = c("FRA", "JPN")))` warned that nothing matched and
  returned all `NA`. Detection now tries the code schemes as well and carries
  the one that worked through to the conversion, so `iso3c`, `iso_a3`, `iso2c`
  and an unrecognised name like `code` all resolve. An explicit `origin` still
  wins, and a column whose name implies a scheme is only read that way if the
  scheme actually resolves it.
* A bounding-box `region` on the **polygon** backend only filters vertices; it
  cannot clip a polygon, so a country crossing the edge keeps a truncated ring
  that `geom_polygon()` closes with a straight chord (France loses 202 of 605
  vertices and the two ends sit 15 degrees apart). Nothing in the returned
  tibble showed it, and the vignette presented the box as clipping the shapes.
  It now warns and points at `geometry = "sf"`, where the clip is a real
  `sf::st_crop()`; `?world_geometry` and the vignette say which is which.
* `attach_geometry()` on a frame that already had geometry multiplied the rows
  instead of refusing. The join is by country, and a polygon frame holds one row
  per *vertex*, so re-attaching joins a country's vertices against themselves:
  the bundled snapshot went from 99,338 rows to **310,977,360**. The call
  declares `relationship = "many-to-many"` -- correctly, since one country really
  does have many vertices -- which switches off dplyr's own guard against
  exactly this. It now errors, and says to pass the country-level table.
* `share_of_world()` on a grouped frame with no `year` column returned a share
  of the **group**, not of the world: `sum()` inside `mutate()` is per group, so
  a frame grouped by continent came back with a column that summed to 5 instead
  of 1, under a name and a help page that both say "world". A panel was already
  safe by accident, because the function regroups by `year` and that replaces the
  caller's groups. It now ignores the grouping in both cases, and says so where
  it would have mattered.
* The verbs that add a column now say when they replace one the caller already
  had. `rank_countries()` overwrote `rank`, `percentile` and `z_score`, and
  `per_capita()`, `share_of_world()`, `growth_rate()`, `index_to()`,
  `lag_by_country()` and `diff_by_country()` overwrote their target column, all
  in silence -- a user's own `rank` column simply vanished. It is a warning, not
  an error, because re-running a verb on its own output is legitimate.
  `standardize_country()` is deliberately exempt: `add` names the columns
  literally, so replacing an existing `continent` is what was asked for.
* `geom_country_labels()` on an `sf` map failed with `rlang`'s internal
  "Column `long` not found in `.data`". The layer reads the polygon backend's
  `long`/`lat` columns, and its own `aes()` was evaluated against the sf frame
  before the guard inside could run. It now errors with its own message and
  points at `ggplot2::geom_sf_text(aes(label = iso3c))`, which is documented on
  the help page too.
* `geom_country_labels()` put every country that crosses the antimeridian on the
  far side of the planet when the frame had no `group` column. `group` is what
  identifies a country's separate pieces, and the label belongs on the largest;
  without it the fallback averaged the raw longitude range, so measured against
  the largest-piece centroid Fiji was 177.8 degrees out, New Zealand 169.6, and
  even the USA 96.6 -- its Aleutian tail dragging the mid-range to the Gulf of
  Guinea. Averaging in wrapped coordinates cuts those to 0.2, 6.9 and 31.4. It
  remains an approximation, and the help page now says that placement is exact
  only while `group` is present.

## Housekeeping

* `gini()` and `theil()` returned a silent `NaN` when the input contained an
  infinity. `Inf` is not `NA`, so it passed `na.rm` and (for Theil) the
  non-positive filter, then made the mean infinite and every share `Inf/Inf`.
  Every other verb propagates an infinity visibly -- `Inf` in, `Inf` out, which
  the caller can see -- but an inequality index has no such value to report, so
  both now warn and return `NA`, as they already did for a zero total weight.
  Infinite `weights` are caught too. `NaN` is still treated as `NA` and dropped.
* `?theil` promised a tibble whenever `groups` is supplied, but every degenerate
  path -- nothing left after `na.rm`, a zero total weight, an infinity -- returns
  a single `NA` instead. The help page now says so.
* `dorling_map(k = 0)` passed validation and then failed inside `cartogram` with
  "all sizes are missing and/or non-positive". `check_number()`'s bounds are
  inclusive, so `lo = 0` admitted a value the next layer cannot use -- the same
  hole the integer ceilings were added to close, at the other end of the range.
  It is now rejected with a message naming `k`; anything above zero still works.
* `?countryatlas` gains an **Options** section. Two of the three options the
  package reads -- `countryatlas.workers` and `countryatlas.gdp_compat` -- were
  described only in this changelog, which is not reference documentation, so a
  reader of the help pages had no way to find them. (`wdj_workers()`'s own
  comment noted that the option was "advertised in NEWS", which is how a bad
  value became reachable.) All three are now documented where they are looked
  for, and a test fails if a future option is read without being listed.
* The test suite runs in a quarter of the time (`R CMD check`'s test phase went
  from 389s to 92s). One block asked `neighbors()` for each country in turn and
  then again for each of that country's neighbours, to confirm the reverse edge
  -- and `neighbors()` recomputes the whole world's `sf::st_touches()` adjacency
  on every call, so that was ~465 rebuilds and 292 seconds, four fifths of the
  suite. `neighbors()` is vectorised, so one call does the same work. The same
  properties are asserted (irreflexive, no repeated pair, every edge symmetric),
  and a failure now names the offending countries rather than only counting
  them.
* `?neighbors` now says to pass a vector rather than loop, since that cost is
  invisible from the outside: every call rebuilds the whole world's adjacency, so
  asking about one country costs the same as asking about all of them, and adding
  countries to a single call only adds the filtering. Measured here, one country
  takes about as long as 153 of them, which makes a loop over them roughly two
  orders of magnitude more work. The note names `country_borders()` as where the
  cost comes from. A test pins the fact the advice rests on -- one
  `country_borders()` call per `neighbors()` call, whatever the length of `x`.
* `?attach_geometry` claimed that Gibraltar, Hong Kong, Macao, Tuvalu and the
  British Virgin Islands have geometry in "no backend at any scale". Only
  Gibraltar does not: the other four are carried by the `sf` backend at
  `scale = "medium"`, which is the very fix the preceding sentence recommends for
  microstates. It was the *no-tile* list from `?world_tiles` -- coincidentally the
  same five names -- pasted into a paragraph about geometry. Corrected, and the
  section's coverage counts (215 snapshot countries; 210, 169 and 214 carried)
  are now pinned by a test, so an upstream Natural Earth change surfaces as a
  failure rather than as silently wrong advice.
* `as_ggsql_source(format = "parquet")` wrote into the **working directory** when
  no `path` was given: the default was the bare relative path
  `"<name>.parquet"`. CRAN policy is that a package writes nowhere but the
  session's temporary directory unless the caller says otherwise. The default is
  now a file of that name under `tempdir()`, and since the function returns the
  path the workflow is unchanged; an explicit `path` still writes exactly where
  you point it. `spin_globe()` already defaulted to `tempfile()`, and no other
  export writes at all.
* `?country_meta` and `?world_snapshot` now say that their `country` columns
  disagree, and why. `country_meta` carries `countrycode`'s English names and
  `world_snapshot` the World Bank's, so 38 of the 215 shared countries are
  labelled differently ("South Korea" against "Korea, Rep."). Each table is
  faithful to its own source and neither is wrong, but joining the two on
  `iso3c` leaves you holding two `country` columns with nothing to explain the
  difference -- the very reconciliation `country_join()` advertises, using the
  same example. The count is pinned by a test, along with the referential
  consistency of all five code columns against `country_meta`.
* `?world_data` and `?country_data` now say where the `country` label comes
  from, because the same call produces two different spellings: a successful
  fetch carries the World Bank's names ("Korea, Rep."), while the country spine
  used when the fetch returns nothing carries the `countrycode` names ("South
  Korea") -- as does every other function in the package. Nothing can reconcile
  that offline, since the World Bank spelling only exists in the response, so
  both pages now point at `iso3c` as the stable key and at
  `convert_country(iso3c, to = "country")` for one consistent set of labels.
* `utils::globalVariables()` declared 29 names where 7 are needed. Emptying it
  and reading what `R CMD check` actually reports showed the rest were covered by
  the `.data$x` idiom the code uses throughout, which needs no declaration at
  all; three of them (`subregion`, `NY.GDP.PCAP.KD`, `gdp_per_capita_2015`) never
  appeared as bare symbols anywhere, only in a comment or as string literals. A
  stale entry is worse than clutter: it silences the "no visible binding" NOTE
  for a *new* bare use of the same name, which is the warning that would
  otherwise catch a typo. A test now fails if a declared name is not a real bare
  symbol in `R/`.
* Six exported functions failed when the package was loaded but not attached --
  `countryatlas::dissolve_country()`, `distance_between()`, `country_groups()`,
  `in_group()`, `tile_map()` and `world_geometry(region = <group name>)` all died
  with "object 'historical_codes' not found" or similar. They referred to the
  bundled datasets by bare name, and a bare name resolves only while the package
  is on the search path: under `countryatlas::fn()` in a script with no
  `library()` call, the lazy-data objects are not reachable. They are now
  `countryatlas::`-qualified. Every test in the suite attaches the package, so
  nothing caught this; a static check now fails if a bare reference reappears.
* `per_capita()` failed when the caller's frame already had a column named
  `.wdj_pop`, the internal name used for the fetched population. The join
  suffixed both sides to `.wdj_pop.x` / `.wdj_pop.y`, so the column the division
  reads came back `NULL` and base R reported "replacement has 0 rows, data has
  2". Any pre-existing column of that name is now dropped before the join. Only
  the branch that fetches population was affected -- passing `pop` explicitly
  never touched it.
* Two verbs leaked someone else's message on an empty frame. `facet_map()` gave
  `ggplot2`'s "Faceting variables must have at least one value", which names
  neither the argument nor the package; it now says the frame has no rows to
  facet, and notes that the other map verbs draw an empty panel instead.
  `geom_country_labels()` ran the centroid summary over nothing, where `range()`
  warns twice and `dplyr` adds a deprecation note on top -- it now returns early,
  silent as it is on a full frame. Every other plotting verb already handled a
  zero-row frame cleanly, either drawing an empty panel or naming the reason it
  cannot.
* `?attach_geometry` now says that geometry is attached once **per row**, not
  once per country. A panel wants exactly that -- one row per country-year, each
  carrying the shape -- but a frame that repeats a country by accident draws it
  more than once, and only the last one painted is visible. dplyr's own
  many-to-many warning is suppressed by the relationship the join declares, so
  nothing signals it.
* `?country_data`'s example quoted a **retired** World Bank indicator. The bank
  replaced the `EN.ATM.CO2E.*` carbon series with the AR5 greenhouse-gas series,
  and the bundled `common_indicators` table had already been updated, but the
  example still asked for `EN.ATM.CO2E.KT` -- so anyone copying it got a warning
  and an all-`NA` column. It now uses `EN.GHG.CO2.MT.CE.AR5`, which returns data.
  `R CMD check` reports examples "OK" without failing on the warning, so nothing
  surfaced this; a test now checks every indicator code quoted in `R/`, `man/`
  or the vignettes against the bundled table.
* `country_groups_tbl` was out of date by two years in four places, while
  carrying an `as_of` stamp of 2026-06-01 that claimed otherwise. **Sweden was
  missing from NATO** (acceded 7 March 2024; Finland had been added, so the table
  had been maintained to 2023 and no further), **Angola was still in OPEC** (left
  1 January 2024), **BRICS still held only its original five** (Egypt, Ethiopia,
  Iran and the UAE joined in January 2024, Indonesia in January 2025), and **The
  Gambia was missing from the Commonwealth** (rejoined 2018). Corrected, so the
  counts are now NATO 32, OPEC 12, BRICS 10 and Commonwealth 56. Saudi Arabia is
  deliberately still absent from BRICS: it was invited in the 2024 round but has
  never confirmed accession. `in_group("Sweden", "NATO")` returned `FALSE` before
  this.
* `options(countryatlas.cache_dir = )` was ignored once a cached fetch had
  happened. The memoised fetcher was built on first use and kept for the rest of
  the session, so relocating the cache afterwards silently kept writing to the
  original directory -- and `?clear_wdi_cache` offers that option as the way to
  relocate the cache without saying it has to be set first. It only ever took
  effect because `clear_wdi_cache()` happened to reset the state. The fetcher is
  now rebuilt when the directory changes, and the "cannot write to the cache
  directory" notice is once per *directory* rather than once per session, so a
  second unwritable location is not swallowed.
* A corrupt cache entry was reported as a World Bank outage. An interrupted write
  leaves a truncated or empty `.rds`, and `readRDS()`'s "unknown input format"
  surfaced under "Could not fetch indicator ... from the World Bank API", sending
  the caller off to debug a connection that was fine -- the same misattribution
  already fixed for an unwritable cache *directory*, now fixed on the read side.
  The warning names the cache and gives the recovery command, which matters
  because the bad entry persists: every later call degrades to the country spine
  until `clear_wdi_cache(disk = TRUE)` is run. A genuine network failure still
  blames the network.
* When the cache directory was unwritable, caching stopped working altogether
  instead of falling back to the session. The in-memory memo that stands in for
  the disk cache lives in one process, but multiple indicators are fetched with
  `parallel::mclapply()`, so each worker warmed a memo and then exited with it:
  every call re-fetched every indicator, hitting the World Bank API again and
  again with nothing to show for it. Fetching is now serial when the memo is
  memory-only -- the repeated round-trips cost far more than the one-shot
  parallel speedup -- and unchanged when the disk cache is available, since a
  disk memo is shared by every worker.
* A failed indicator was dropped from the result without a word, whenever more
  than one indicator was requested. `fetch_one_safe()` degrades gracefully and
  warns -- "Could not fetch indicator ... from the World Bank API", or the
  corrupt-cache variant -- but it runs inside `parallel::mclapply()`, which
  brings back a worker's *value* and discards the conditions it signalled. Since
  having several indicators is exactly what makes the fetch fork, and
  `parallel = TRUE` is the default, the common case was the silent one: a column
  simply missing from the table with no explanation. A single indicator, which
  never forks, warned correctly -- which is why this went unnoticed. Conditions
  are now carried back and re-signalled in the calling process, on the serial
  path too so both report identically, and one problem is reported once even if
  two entries name the same series.
* Country lookups silently returned `NA` in Turkish, Azeri and Crimean Tatar
  locales. `toupper()` and `tolower()` follow `LC_CTYPE`, and in those locales
  `i` and `I` are not a case pair: `toupper("idn")` returns a *dotted* capital
  I, not `"IDN"`, and `tolower("ISO3C")` returns a *dotless* i. Five places
  folded an ASCII identifier that way and then compared it against plain ASCII,
  so every ISO code containing an `i` (IDN, IND, IRL, IRN, ISL, ISR, ITA, BIH,
  CIV, FIN, ...) failed to resolve. The failures were quiet and the blast radius
  uneven: `world_geometry(region = c("ind", "chn"))` returned Ivory Coast,
  Indonesia, Isle of Man and India -- one unfoldable element made the whole
  vector fall through to *name* matching, which then matched on substrings;
  `dissolve_country("SOUTH VIETNAM")` stopped finding its alias; and
  `join_world()` on a frame with `ISO3C` and `geo` columns picked `geo`, joining
  on the wrong column entirely. Identifier folding is now done with an explicit
  ASCII table (`ascii_upper()` / `ascii_lower()`) and does not consult the
  locale.

  This fixes countryatlas's own folding, which covers every path keyed on an ISO
  code, a column name or an alias. It cannot fix matching on a country *name*:
  that goes through `countrycode`, whose regexes are themselves locale-sensitive
  (`countrycode("Ireland", "country.name", "iso3c")` is `NA` under `tr_TR`). So
  a user with `LC_COLLATE=tr_TR` still sees name-keyed gaps -- notably the
  polygon backend, which labels its geometry by joining region *names* to codes,
  so `world_geometry(region = "IND")` comes back with 21 rows of Siachen Glacier
  instead of India. Working around that would mean forcing the C locale around
  every `countrycode` call, which risks mangling accented names for everyone
  else; it is left for upstream.
* The two-core cap that CRAN policy requires of a check was applied only when
  `_R_CHECK_LIMIT_CORES_` held the exact string `"TRUE"`. `R CMD check
  --as-cran` does set it to that -- but only when it is not already set, so the
  value that actually arrives is whatever the check flavour or CI exported, and
  R's own parser for these variables reads `"true"`, `"True"`, `"T"`, `"1"`,
  `"yes"`, `"Yes"` and `"YES"` as true as well. Under any of those spellings the
  cap did not apply and a multi-indicator fetch forked `detectCores() - 1`
  workers in the middle of a check. The test is now inverted: a value that is
  set and does not explicitly parse as false means "limit", which also covers
  `"warn"`. An explicit `"false"`, `"F"`, `"0"` or `"no"` is still honoured as a
  deliberate opt-out.
* `?world_data`'s example called `world_data(2020)` unconditionally, and the
  default `geometry = "polygon"` backend comes from the suggested `maps`
  package. `R CMD check` runs `\donttest{}` blocks, so on a check flavour
  configured without suggested packages -- CRAN runs one -- that example failed
  with "The package \"maps\" is required for the polygon geometry backend",
  taking the whole examples step down with it. Writing R Extensions requires
  code that uses a suggested package to be conditional, examples included; the
  call is now guarded with `requireNamespace("maps")`. The second call in the
  block passes `geometry = "none"` and needs nothing beyond the hard
  dependencies, so it is left to run unconditionally.
* The `beyond-the-choropleth` vignette failed to build wherever `rnaturalearth`
  was absent. Its chunk guard was `has_sf <- requireNamespace("sf")`, but the sf
  geometry backend gates on three packages -- `sf`, `rnaturalearth` and
  `rnaturalearthdata` -- so on a machine with sf but without the Natural Earth
  data the guarded chunk evaluated to `TRUE`, ran, and stopped `R CMD build`
  with "The packages \"rnaturalearth\" and \"rnaturalearthdata\" are required
  for the sf geometry backend". The other two vignettes already tested for
  `rnaturalearth`; all three now test for the same trio the code itself gates
  on. Three tests had the same incomplete guard and errored rather than
  skipping in that configuration; they now share a `skip_if_no_sf_geometry()`
  helper.
* New hex logo, drawn by the package itself (`data-raw/hex_logo.R`): an
  orthographic globe — `globe_map()`'s projection — carrying a viridis
  choropleth of `world_snapshot` GDP per capita on Natural Earth geometry
  joined by `attach_geometry()`, with `spike_map()`-style population spikes
  rising off the horizon and the binned-legend swatches under the wordmark.
* The `gdp_per_capita_2015` compatibility alias (a one-cycle deprecation shim
  from 1.0.0) is now opt-in: set `options(countryatlas.gdp_compat = TRUE)` to
  restore it. The default is `FALSE`, so `world_data()` no longer emits a
  duplicate column.
* `world_snapshot` refreshed to year **2024** (was 2022) and rebuilt with the
  latest WDI data and curated overrides.
* `country_groups_tbl` membership date bumped to 2026-06-01 (was 2024-01-01).
* `?world_snapshot` was out of sync with the rebuilt data (missing the
  "Snapshot year: 2024" note); regenerated.
* Fixed a stray orphaned code fence at the end of the *countryatlas and
  ggsql* vignette that broke its markdown structure.
* `.Rbuildignore` now excludes the session-local `.claude/` directory, which
  `git` ignores but `R CMD build` does not, so it was shipping in the tarball
  and tripping `R CMD check`'s "hidden files and directories" NOTE.
* Comments in `R/overrides.R` are ASCII-only, so no source file carries
  non-ASCII characters outside a deliberate `\U` escape.
* `?world_snapshot` no longer splits a code span across two source lines, which
  had left the checked-in `.Rd` disagreeing with what `roxygen2` regenerates.
* `beta_convergence()` failed with a bare `"subscript out of bounds"` when the
  initial levels had no spread across countries. A constant predictor makes
  `lm()` return an `NA` coefficient, which `summary()` then drops entirely, so
  the lookup for it fell off the end. It now says that the initial levels have
  no spread and why that matters.
* The forking path is now tested. `fetch_wdi(parallel = TRUE)` is the default
  for a multi-indicator request, so `wdj_lapply()`'s `mclapply` branch runs on
  one of the package's busiest code paths, yet no test reached it -- every other
  test used a single indicator or passed `parallel = FALSE`. Confirmed: a
  parallel fetch is identical to the serial one, forking preserves order, `...`
  reaches the workers, `wdj_workers()` honours `options(countryatlas.workers)`
  and CRAN's two-core limit, and an error inside a fork is surfaced rather than
  left as a `try-error` for downstream code to trip over.
* The World Bank fetch and assembly path is now tested offline. It needs the
  network, so it had no coverage at all despite holding the least obvious logic
  in the package: `fetch_wdi()`'s multi-indicator reduce-merge (shared keys are
  coalesced rather than suffixed, and values stay aligned per country-year),
  its degradation when one indicator of several fails,
  `country_data(latest = TRUE)`'s "most recent non-NA" collapse (which opens the
  window at 1960 and skips a missing latest year), the panel key, the
  duplicate-key case where two `iso2c` codes map to one `iso3c`, and that
  `cache = TRUE` really short-circuits a repeated fetch. No defects were found;
  the tests pin the behaviour.
* `spin_globe()` validates `n_frames` / `fps` / `width` / `height` / `lat`
  before gating on `gifski` / `magick`, matching how `globe_map()` orders the
  two: a bad argument is the caller's bug and the message should not depend on
  which optional packages happen to be installed.
* `tile_map()` phrased the missing-`iso3c` error differently from the three
  other verbs performing the identical check; all four now read the same.
* Half the examples that were marked `\dontrun{}` now actually run: it covered
  14 of the 55 documented topics and now covers 7. Nine verbs gained executable
  examples -- `locate_country()`, `country_borders()`, `neighbors()`,
  `morans_i()`, `simplify_geometry()`, `bivariate_map()`, `cartogram_map()`,
  `dorling_map()` and the polygon-backend `globe_map()` -- having been
  unrunnable only because their examples made a live World Bank fetch. Driven
  by the bundled `world_snapshot` instead, and guarded with
  `requireNamespace()`, they are `\donttest{}` examples that execute in under
  half a second each. The safe form of `clear_wdi_cache()` is now a live
  example too. `\dontrun{}` remains
  only where the code genuinely cannot run in a check (a network fetch, an HTML
  widget, a written GIF, `ggsql` >= 0.4.1, or deleting files).
* The tests guarding this release's fixes were verified by mutation: each fix
  was reverted in a scratch copy and the suite had to fail. 35 mutations, all
  now detected -- but four were not at first, and each pointed at a real gap:
  * `is.na()` is `TRUE` for `NaN` as well, so the checks on `theil()`'s
    zero-weight result and its shares at perfect equality passed whether the
    value was the fixed `NA` or the `NaN` the bug produced. Both now assert the
    exact value.
  * Nothing verified that quantile breaks are computed on one value per country
    rather than per polygon vertex -- the fix that forced this major version
    bump. Removing the de-duplication, or flipping the flag that controls it on
    either `world_map()` or `globe_map()`'s polygon backend, broke no test.
    There are now checks on the helper, on both call sites, and on the property
    that matters: roughly equal numbers of *countries* per colour.
  * `interactive_map(tooltip = )` was unprotected: the existing tests assert the
    returned object's class, which passes whether the argument is honoured or
    silently dropped -- exactly the pre-2.0.0 bug. Both the `"ggiraph"` and
    `"leaflet"` engines are now checked on the column they are actually handed.
* Degenerate-but-valid input is now covered by tests: perfect equality
  (`gini()` / `theil()` return `0`, not `NaN`), zero-variance columns
  (`NaN` z-scores and `NA` correlations rather than errors), duplicate
  `(iso3c, year)` panel rows, poles and antipodal great circles, collinear
  rings, all-`NA` and all-zero fill columns, and single-country frames.
* `?distance_between` and `?country_meta` now state which countries have no
  bundled centroid. `country_meta` is assembled from `countrycode::codelist`,
  which has no Kosovo row, so `distance_between("Kosovo", "Serbia")` is `NA`
  even though `neighbors("Kosovo")` and `country_borders()` know about it -- and
  ten small or dependent territories have a row but no centroid. The `@return`
  already said `NA` was possible; it did not say which countries, and the
  asymmetry with the geometry backends was surprising.
* The same double-counting affected three more places, all gated on the
  presence of a `group` column -- which polygon frames have and `sf` frames do
  not:
  * `correlate_indicators()` reported `n` and `r` over geometry rows rather than
    countries. That column exists precisely so a correlation computed on a few
    countries cannot masquerade as a world fact, so an inflated `n` defeated the
    point.
  * `audit_coverage()` reported the wrong country count and a wrong `NA` rate
    for every indicator.
  * `bubble_map(backend = "sf")` drew two bubbles for a divided country, where
    the polygon path already guaranteed one per country.
  All three now reduce whenever an `iso3c` column is present.
* Quantile and jenks breaks on the `sf` backend double-counted divided
  countries. The de-duplication added in this release skipped the `sf` path on
  the assumption that Natural Earth is one row per country, but it is not:
  Cyprus occupies two rows sharing one `iso3c` at 110m, as do Cyprus and India
  at 50m. Breaking on the raw column shifted the cut points enough to move real
  countries into the wrong bin -- Saudi Arabia and Libya changed colour in the
  bundled snapshot at `n_bins = 5`. Both backends now de-duplicate on the key,
  so "one value per country" holds exactly rather than nearly.
* `convert_country(x, to = "calling_code")` returned alpha-3 country codes
  instead of telephone calling codes -- `"FRA"` where `33` was meant. The
  shortcut was mapped to `countrycode`'s `genc3c` column, which is an ISO-style
  three-letter code, not a dialling prefix; it now maps to the `telephone`
  column, so France gives `33`, the USA `1` and Japan `81`. A source comment
  claimed the limitation was "documented as best-effort", but `?convert_country`
  never mentioned `calling_code` at all; the shortcut is now listed there.
* The `Description` field -- the text CRAN renders on the package page --
  advertised nine map idioms while the package ships eleven: `spike_map()` and
  `facet_map()` (small multiples) were missing from the vocabulary list, and the
  analysis-helper examples predated this release's inequality and convergence
  statistics. Every idiom it names now corresponds to an exported verb.
* `?countryatlas` listed `morans_i()` under "Core data assembly" while
  `_pkgdown.yml` listed it under "Analysis helpers", so the two navigational
  indexes described the same function as two different kinds of thing. It is a
  spatial statistic, so it now sits with `gini()`, `theil()` and the convergence
  measures on both surfaces.
* The `@seealso` cross-references are reciprocal. All three the package had
  pointed one way only: a reader of `?gini` was sent to `theil()` but a reader
  of `?theil` was sent nowhere, and likewise for
  `beta_convergence()`/`sigma_convergence()` and
  `dissolve_country()`/`check_country_match()`. `?theil` did not link to `gini()`
  at all -- it named Gini in prose without a cross-reference. The four related
  diagnostics (`check_country_match()`, `repair_country_names()`,
  `dissolve_country()`, plus `historical_codes`) now all reference each other.
* Every page taking a `projection` argument now says where the valid values
  are. Only `world_map()` enumerated the 13 projections and only
  `world_geometry()` pointed at it; the other eight entries said no more than
  "Projection." (`bivariate_map()`) or "Projection options for the `sf`
  backend", leaving a reader with nothing to go on. Relatedly, the three pages
  that document `projection` and `recenter` together described only the
  projection, so `recenter`'s meaning -- a central meridian -- was missing from
  `world_data()`, `join_world()` and `attach_geometry()`.
* The `rnaturalearthhires` requirement is now documented on every page that
  takes a `scale` argument, not just `?world_geometry`. Seven topics --
  `world_data()`, `join_world()`, `attach_geometry()`, `locate_country()`,
  `country_borders()`, `neighbors()` and `morans_i()` -- described `scale`
  without mentioning that `"large"` is unobtainable from CRAN, so a reader of
  any of those pages met the gate with no warning.
* `scale = "large"` was offered as a plain option but needs the
  `rnaturalearthhires` package, which is not on CRAN and is not in `Suggests`.
  Left ungated, `rnaturalearth` responded by trying to install it into the
  user's library from a non-CRAN repository and then failing obscurely. It is
  now gated with a message naming the package and the repository to get it
  from, and pointing at `scale = "medium"` (50m) as the option that needs
  nothing extra. `?world_geometry` documents the requirement, and the
  *sf & projections* vignette no longer demonstrates the scale most readers
  cannot run.
* `?country_borders` recommended a graph recipe that produced nonsense.
  `igraph::graph_from_data_frame()` treats the *first two* columns as the edge
  endpoints, and `country_borders()` returns `iso3c_a`, `country_a`, `iso3c_b`,
  `country_b` -- so columns 1 and 2 are both endpoint *A*, and passing the whole
  tibble built edges from each country's code to its own name (56 vertices
  instead of 37 for Europe, every French edge running `FRA` to `"France"`). The
  documented call now passes only the two code columns.
* `?neighbors` and `?country_borders` now warn that `igraph` also exports a
  `neighbors()` -- taking a graph and a vertex rather than country names -- so
  whichever package is attached later wins. `?country_borders` recommends
  `igraph` for turning the adjacency into a graph, which walks users straight
  into the clash, so both pages now say to qualify the call as
  `countryatlas::neighbors()`. It is the only collision between this package's
  exports and any of `dplyr`, `ggplot2`, `tidyr`, `tibble`, `sf`, `maps`, `WDI`,
  `countrycode`, `scales`, `leaflet`, `plotly`, `igraph`, `raster`, `terra`,
  `purrr`, `stringr`, `forcats`, `readr` or the base packages.
* `?country_overrides` now documents why every name in the override table is
  plain ASCII: ASCII spellings match in any locale, whereas accented spellings
  rely on `countrycode`'s own matching and resolve to `NA` under a non-UTF-8
  locale (`LC_CTYPE=C`). The note points at `iconv(x, to = "ASCII//TRANSLIT")`
  for input that may carry accents.
* The test suite is now green under CRAN's `noSuggests` configuration
  (`_R_CHECK_DEPENDS_ONLY_=true`), which runs with every optional package
  absent. Four tests called `globe_map(backend = "polygon")` or `morans_i()`
  without guarding on `mapproj` / `sf`, so they errored on the dependency gate
  instead of exercising what they were written to check.
* The quantile/jenks binning that `world_map()` and both `globe_map()` backends
  perform lived as three near-copies kept in step by hand; it is now one
  internal helper. Verified behaviour-preserving by comparing the rendered fill
  of every style x `n_bins` x backend combination before and after (50
  fingerprints, ~2.6M values, all identical).
* Documented `\value` claims are now asserted as executable contracts, so Rd
  prose cannot drift from the code in silence. The 36 exports whose `\value`
  makes a specific structural promise -- named columns, a single row, an
  attached `"model"` object, a length matching the input -- are covered; the
  rest return a `ggplot`, a layer or a widget and are checked by their own
  tests. Every claim audited was already accurate; the tests keep it that way.
* The four exports that had no test call site at all -- `wdi_search()`,
  `clear_wdi_cache()`, `animate_world()` and `cartogram_map()` -- are covered,
  including `cartogram_map(type = "contiguous")` (the default type, previously
  never exercised) and `wdi_search()`'s zero-match and single-match paths.
* The README's "optional features at a glance" table is corrected against what
  the code actually gates on: `spin_globe()` was listed as needing only `maps` +
  `mapproj` when it also hard-requires `gifski` or `magick`; the `ggsql` row
  overstated the requirements of `as_ggsql_source()` (which never needs `ggsql`)
  and understated the version `interactive_map(engine = "ggsql")` needs; and
  `locate_country()`, `flow_map()` and `bubble_map()` were missing.
* The *countryatlas and ggsql* vignette said `DRAW spatial` "was added in 0.4.1"
  as plain fact; it now says that version is newer than what CRAN ships, which
  is why the query-executing chunks are shown but not evaluated.
* The package-level overview (`?countryatlas`) was missing `simplify_geometry()`
  and `clear_wdi_cache()` from its section list, though `_pkgdown.yml` had both.
* The set of ISO codes the package treats as countries was computed in two
  places (name matching and the World Bank aggregate filter); it now comes from
  one internal helper, which region resolution uses as well, so the three
  callers cannot drift apart.
* New offline test suites pin the things a structural test cannot: closed-form
  anchors for the hand-rolled numerical kernels (haversine distance, spherical
  polygon area, great-circle interpolation, Gini/Theil, sigma and beta
  convergence, Moran's I against an independently built weights matrix) and
  internal-consistency checks on every bundled dataset (no duplicate or unknown
  `iso3c`, coordinates in range, one country per `world_tiles` cell,
  `historical_codes` in step with its alias table, and `country_meta`
  centroids still agreeing with `polygon_centroids()`).
* README and vignettes now demonstrate every exported function:
  `wdi_search()`, `country_codes()`, `complete_years()`, `growth_rate()` /
  `index_to()`, `repair_country_names()`, `country_join_all()`,
  `locate_country()` and `facet_map()` gained worked examples, and the
  vignettes prefer `country_overrides()` over the soft-deprecated
  `wdj_overrides()`. The README's rendered output and figures were stale
  (pre-dating the quantile-breaks fix and the `gdp_per_capita_2015` opt-in)
  and have been re-rendered from the 2.0.0 code.
* `geofacet` is dropped from `Suggests`: no code ever used it, and
  `?tile_map` / the README claimed a `geofacet`-backed small-multiples
  feature that did not exist. Facet a `tile_map()` like any other `ggplot`,
  or use `facet_map()` for choropleth small multiples.
* The README's figures are shipped in the tarball again, so the images on the
  CRAN package page resolve. `.Rbuildignore` excluded the generated `.png`s
  but not the (much larger) `.gif`, which left six of the seven images
  broken.
* `?world_snapshot`'s `@format` said "two elements" while listing three, and
  advertised an `sf` element that is `NULL` in the released package. It now
  documents what actually ships and points at `attach_geometry()` for
  geometry.
* `?attach_geometry` documents which countries each geometry backend actually
  carries. Rows with no matching geometry are dropped silently, and the `sf`
  backend's `scale` changes *which* countries exist rather than only how
  detailed they are: of the 215 countries in `world_snapshot`, the default
  `scale = "small"` (110m) maps 169 and `scale = "medium"` maps 214. Five
  territories (Gibraltar, Hong Kong, Macao, Tuvalu, the British Virgin
  Islands) are in no backend at any scale.
* `?world_tiles` and `?tile_map` said "one square per country" without saying
  how many. The grid is the 239 `country_meta` rows that have a bundled
  centroid, so the 10 without one have no tile and `tile_map()` silently drops
  `data` rows keyed on them. Both are now documented, and a test pins the
  grid to that definition.

# countryatlas 1.0.0

A single, comprehensive release that takes the package from a one-function proof
of concept to a complete toolkit for joining world data to maps. The spirit is
unchanged — *ISO codes as the universal join key, one call to a map-ready
table* — but pushed to its full potential.

## Breaking-ish changes

* `world_data()` is generalised but backward-compatible: `world_data(2020)`
  still returns the classic polygon-backed, GDP-per-capita tibble. The only
  visible change is the column name `gdp_per_capita_2015` → `gdp_per_capita`.
  A one-cycle deprecation shim keeps `gdp_per_capita_2015` available as an alias
  (toggle with `options(countryatlas.gdp_compat = FALSE)`).
* The 16 regions the previous version silently dropped (Kosovo, Micronesia, the
  Virgin Islands, Saint Martin, Bonaire/Saba/Sint Eustatius, the Canary Islands,
  Madeira/Azores, …) are now **matched** via [`wdj_overrides()`] instead of
  deleted, so they appear on maps. Diffs of map output will show increased
  coverage.

## New: core data assembly

* `world_data()` gains `indicator` (one or many WDI codes; named vectors drive
  clean column names), multi-year **panels**, an `sf` backend
  (`geometry = "sf"`), `region` subsetting, `latest`, projections and caching.
* `country_data()` — the lightweight, one-row-per-country analysis table.
* `world_geometry()` — projected, region-subset geometry (countries, centroids,
  coastline, borders, graticule, ocean).

## New: the join engine (exposed for *your* data)

* `standardize_country()`, `join_world()`, `attach_geometry()`, `country_join()`.

## New: diagnostics

* `check_country_match()`, `wdj_overrides()`, `audit_coverage()` — never lose a
  country silently.

## New: reference data & translation

* `convert_country()` (flags, currency, tld, research codes), `country_codes()`,
  `country_groups()` / `in_group()`, `wdi_search()`.
* Bundled datasets: `world_snapshot`, `country_meta`, `common_indicators`,
  `country_groups_tbl`, `world_tiles`.

## New: analysis helpers

* `per_capita()`, `aggregate_regions()`, `rank_countries()`, `complete_years()`.

## New: visualization

* `world_map()` (continuous / binned / quantile / jenks / categorical),
  `bubble_map()`, `bivariate_map()`, `cartogram_map()`, `tile_map()`,
  `flow_map()`, `animate_world()`, `interactive_map()`, `geom_country_labels()`,
  `theme_world_map()`.

## Performance & offline

* WDI fetches are memoised with an optional on-disk cache; multiple indicators
  are fetched in parallel (`parallel::mclapply`) where supported.
  See `clear_wdi_cache()`.
* The bundled `world_snapshot` lets every example, test and vignette run offline
  and deterministically.

## Engineering

* Namespace hygiene (targeted `@importFrom` instead of blanket `@import`).
* Input validation with friendly `cli` / `rlang` errors.
* A `testthat` (3e) suite; network calls are skipped offline and on CRAN.
* Algebraic invariants alongside the closed-form anchors. An anchor pins one
  value, which a wrong divisor can still satisfy for a single input; these pin
  the relationships instead -- shares summing to one within each year,
  `per_capita()` multiplying back to the original value, a deflator equal to
  the base year and a PPP factor of one being identities, compounding
  `growth_rate()` walking the series back out, `index_to()` landing exactly on
  `to` at the base year, ranks forming a permutation, and `gini()`/`theil()`
  reaching their analytic bounds and staying scale-free.
* The test run is kept out of the checking account's file space, so
  `R CMD check` cannot report "new files in some other directories" -- the NOTE
  CRAN raised against 1.0.0. The redirect now sets `R_USER_CACHE_DIR` as well
  as `XDG_CACHE_HOME`: `tools::R_user_dir(pkg, "cache")` reads the former
  first, so setting only the fallback left the redirect at the mercy of the
  machine, and wherever `R_USER_CACHE_DIR` happened to be set a suggested
  package's cache still escaped to the real user directory.
* Vignettes and a `pkgdown` site.
* Refreshed CI: R-CMD-check, test-coverage and pkgdown workflows.
* Heavy spatial dependencies (`sf`, `rnaturalearth`, `cartogram`, `biscale`,
  `geofacet`, `gganimate`, `leaflet`, …) are all in `Suggests` and gated by
  `rlang::check_installed()`, so the base install stays light.

Group memberships in `country_groups_tbl` are point-in-time as of 2024-01-01.

# countryatlas 0.1.0

* Initial experimental release with a single `world_data(year)` function.
