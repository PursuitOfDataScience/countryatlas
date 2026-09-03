# Internal-consistency checks on the bundled datasets. They are the package's
# core asset and are rebuilt by hand from data-raw/, so a bad rebuild would
# otherwise only surface as wrong maps. All offline and deterministic.

known_iso3c <- function() {
  c(unique(stats::na.omit(countrycode::codelist$iso3c)), "XKX")
}

test_that("country_meta is a clean one-row-per-country table", {
  cm <- countryatlas::country_meta
  expect_equal(anyDuplicated(cm$iso3c), 0L)
  expect_false(anyNA(cm$iso3c))
  expect_length(setdiff(cm$iso3c, known_iso3c()), 0L)
  expect_true(all(is.na(cm$centroid_lon) | abs(cm$centroid_lon) <= 180))
  expect_true(all(is.na(cm$centroid_lat) | abs(cm$centroid_lat) <= 90))
  expect_true(all(is.na(cm$capital_lon) | abs(cm$capital_lon) <= 180))
  expect_true(all(is.na(cm$capital_lat) | abs(cm$capital_lat) <= 90))
  expect_true(all(is.na(cm$area_km2) | cm$area_km2 > 0))
  expect_true(is.logical(cm$landlocked))
  # Every range check above is of the form `is.na(x) | in_range(x)`, which is
  # what lets a country with no capital through -- and which also passes
  # vacuously if a column is entirely NA. A data-prep bug that blanked one would
  # not fail any assertion above it, so pin the coverage too. Measured shares
  # are 96% for the centroids and area and 84% for the capitals.
  for (col in c("centroid_lon", "centroid_lat", "area_km2")) {
    expect_gt(mean(!is.na(cm[[col]])), 0.9)
  }
  for (col in c("capital_lon", "capital_lat")) {
    expect_gt(mean(!is.na(cm[[col]])), 0.75)
  }
})

test_that("country_meta centroids still agree with polygon_centroids()", {
  # The bundled centroids were built with the same largest-piece rule the live
  # geometry uses; drift between the two would silently change
  # distance_between() / bubble_map() placement.
  skip_if_not_installed("maps")
  live <- world_geometry("centroids", geometry = "polygon")
  cm <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
  both <- merge(as.data.frame(cm), as.data.frame(live), by = "iso3c",
                suffixes = c("_meta", "_live"))
  expect_gt(nrow(both), 150L)
  gap <- countryatlas:::haversine_km(
    both$centroid_lon_meta, both$centroid_lat_meta,
    both$centroid_lon_live, both$centroid_lat_live
  )
  expect_true(all(is.na(gap) | gap < 1))
})

test_that("country_groups_tbl memberships are well formed", {
  g <- countryatlas::country_groups_tbl
  expect_false(anyNA(g$iso3c))
  expect_length(setdiff(g$iso3c, known_iso3c()), 0L)
  expect_equal(anyDuplicated(g[, c("group", "iso3c")]), 0L)
  expect_true(all(nzchar(g$country) & !is.na(g$country)))
  # The group list ?country_groups documents must be exactly what ships.
  expect_setequal(
    unique(g$group),
    c("EU", "OECD", "G7", "G20", "BRICS", "ASEAN", "EFTA", "Commonwealth",
      "OPEC", "EuroZone", "NATO", "Nordic", "Visegrad", "Mercosur", "GCC")
  )
  # Groups whose size is fixed by name or treaty.
  expect_equal(sum(g$group == "G7"), 7L)
  expect_equal(sum(g$group == "EU"), 27L)
  expect_equal(sum(g$group == "Visegrad"), 4L)
  expect_equal(sum(g$group == "Nordic"), 5L)
})

test_that("world_tiles is a valid one-country-per-cell grid", {
  wt <- countryatlas::world_tiles
  expect_equal(anyDuplicated(wt$iso3c), 0L)
  expect_length(setdiff(wt$iso3c, known_iso3c()), 0L)
  # Two countries sharing a cell would silently overplot in tile_map().
  expect_equal(anyDuplicated(wt[, c("row", "col")]), 0L)
  expect_true(all(wt$row >= 1L & wt$col >= 1L))
})

test_that("historical_codes and historical_aliases() stay in step", {
  hc <- countryatlas::historical_codes
  expect_length(setdiff(hc$iso3c, known_iso3c()), 0L)
  expect_false(anyNA(hc$iso3c))
  expect_true(all(hc$dissolved >= 1945 & hc$dissolved <= 2011))
  expect_equal(anyDuplicated(hc[, c("historical", "iso3c")]), 0L)
  aliases <- countryatlas:::historical_aliases()
  # Every entity must be reachable by name, and every alias must resolve.
  expect_true(all(tolower(unique(hc$historical)) %in% names(aliases)))
  expect_true(all(unname(aliases) %in% hc$historical))
  # The stored successor name must match what convert_country() would give.
  expect_equal(hc$country,
               convert_country(hc$iso3c, to = "country", from = "iso3c",
                               warn = FALSE))
})

test_that("common_indicators is a clean catalogue", {
  ci <- countryatlas::common_indicators
  expect_equal(anyDuplicated(ci$name), 0L)
  expect_equal(anyDuplicated(ci$code), 0L)
  expect_true(all(grepl("^[A-Z]{2}\\.", ci$code)))
  expect_true(all(nzchar(ci$description)))
})

test_that("world_snapshot matches its documented shape and plausible ranges", {
  ws <- countryatlas::world_snapshot
  expect_setequal(names(ws), c("countries", "sf", "year"))
  expect_length(ws$year, 1L)
  expect_gte(ws$year, 1960)
  # ?world_snapshot states sf is NULL in the released package.
  expect_null(ws$sf)
  sc <- ws$countries
  expect_equal(anyDuplicated(sc$iso3c), 0L)
  expect_length(setdiff(sc$iso3c, known_iso3c()), 0L)
  expect_true(all(is.na(sc$gdp_per_capita) | sc$gdp_per_capita > 0))
  expect_true(all(is.na(sc$population) | sc$population > 0))
  expect_true(all(is.na(sc$life_expectancy) |
                    (sc$life_expectancy > 0 & sc$life_expectancy < 100)))
  expect_true(all(is.na(sc$co2_per_capita) | sc$co2_per_capita >= 0))
  # Same vacuity guard as country_meta above: an all-NA column satisfies every
  # `is.na(x) | ...` range test. Measured: population and life_expectancy are
  # complete, co2 94%, gdp 89%.
  for (col in c("population", "life_expectancy")) {
    expect_equal(sum(is.na(sc[[col]])), 0L)
  }
  expect_gt(mean(!is.na(sc$co2_per_capita)), 0.85)
  expect_gt(mean(!is.na(sc$gdp_per_capita)), 0.8)
  expect_true(is.factor(sc$income))
  expect_setequal(levels(sc$income), countryatlas:::income_levels())
})

test_that("the override table maps only to codes the package can resolve", {
  ov <- country_overrides()
  expect_equal(anyDuplicated(names(ov)), 0L)
  expect_true(all(nzchar(names(ov))))
  expect_length(setdiff(unname(ov), known_iso3c()), 0L)
  # Every target must survive the package's own iso3c round-trip.
  expect_false(anyNA(countryatlas:::wdj_to_iso3c(unname(ov), origin = "iso3c")))
})

test_that("the data-raw override snapshot is still in sync with wdj_overrides()", {
  # data-raw/overrides_snapshot.R keeps a standalone copy so the dataset build
  # does not depend on the installed package. Its header says "keep in sync",
  # which a comment cannot enforce -- drift here would silently change
  # country_meta / world_tiles on the next rebuild. data-raw is
  # .Rbuildignore'd, so this only runs from a source checkout.
  path <- testthat::test_path("..", "..", "data-raw", "overrides_snapshot.R")
  skip_if_not(file.exists(path), "data-raw/ not present (installed package)")
  env <- new.env(parent = globalenv())
  sys.source(path, envir = env)
  snapshot <- get("wdj_overrides_snapshot", envir = env)()
  live <- country_overrides()
  expect_setequal(names(snapshot), names(live))
  expect_equal(snapshot[order(names(snapshot))], live[order(names(live))])
})

test_that("the override table is ASCII, so it matches in any locale", {
  # Accented spellings rely on countrycode's own matching, which needs a UTF-8
  # locale; the ASCII spellings in this table resolve everywhere, which is why
  # they are the ones curated here. Non-ASCII names would silently stop
  # matching under LC_CTYPE=C.
  ov <- country_overrides()
  expect_false(any(grepl("[^ -~]", names(ov))))
  expect_false(any(grepl("[^ -~]", unname(ov))))
  # The de-accented spellings the table exists to cover must all resolve.
  deaccented <- c("Curacao", "Saint Barthelemy", "Micronesia", "Canary Islands",
                  "Azores", "Kosovo")
  expect_false(anyNA(convert_country(deaccented, warn = FALSE)))
})

test_that("map-ready frames are reduced to one row per country everywhere", {
  # Natural Earth gives divided countries two rows sharing one iso3c (Cyprus at
  # 110m), and an sf frame has no `group` column -- so code that gated
  # de-duplication on `group` silently double-counted them.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  expect_gt(nrow(sfd), dplyr::n_distinct(sfd$iso3c))    # duplicates exist
  dd <- dplyr::distinct(tibble::as_tibble(sfd), .data$iso3c, .keep_all = TRUE)

  # correlate_indicators: `n` must count countries, not geometry rows.
  expect_equal(as.data.frame(correlate_indicators(sfd)),
               as.data.frame(correlate_indicators(dd)))
  # audit_coverage: `n` and every NA rate likewise.
  expect_equal(audit_coverage(sfd)$na_rates, audit_coverage(dd)$na_rates)
  expect_equal(unique(audit_coverage(sfd)$na_rates$n),
               dplyr::n_distinct(sfd$iso3c))

  # bubble_map(backend = "sf") must draw one bubble per country it has a value
  # for, as the polygon path already guaranteed -- never one per geometry
  # piece, and never an invisible point for a country with no value (which
  # ggplot2 drops at draw time with a bare "Removed n rows").
  p_sf <- suppressWarnings(bubble_map(snap, population, backend = "sf"))
  built <- ggplot2::ggplot_build(p_sf)
  pts <- built$data[[length(built$data)]]
  expect_lte(nrow(pts), dplyr::n_distinct(sfd$iso3c))
  expect_false(anyNA(pts$size))
  # The count drawn is exactly the count claimed.
  expect_equal(nrow(pts),
               attr(p_sf, "countryatlas_provenance")$coverage$n_shown)
})

test_that("distance_between returns NA exactly where a centroid is missing", {
  # Documented in ?distance_between: country_meta has no centroid for a handful
  # of small territories, and no row at all for Kosovo (countrycode has none).
  # Asserted as a property, so a future data rebuild that adds them makes this
  # test fail and prompt a doc update rather than silently diverging.
  meta <- countryatlas::country_meta
  has_centroid <- meta$iso3c[!is.na(meta$centroid_lon) & !is.na(meta$centroid_lat)]
  no_centroid <- setdiff(meta$iso3c, has_centroid)

  # A pair of well-covered countries gives a real distance.
  expect_gt(distance_between("FRA", "DEU", origin = "iso3c"), 0)
  # Codes with a row but no centroid give NA.
  if (length(no_centroid)) {
    expect_true(all(is.na(distance_between(no_centroid, "FRA", origin = "iso3c"))))
  }
  # Kosovo resolves to XKX everywhere else, but has no row here.
  expect_equal(convert_country("Kosovo", to = "iso3c"), "XKX")
  expect_false("XKX" %in% meta$iso3c)
  expect_true(is.na(distance_between("Kosovo", "Serbia")))
  # Every code that DOES have a centroid gives a finite distance.
  sample_codes <- utils::head(has_centroid, 40)
  expect_false(anyNA(distance_between(sample_codes, "FRA", origin = "iso3c")))
})

test_that("world_tiles is exactly the country_meta rows that have a centroid", {
  # ?world_tiles documents the grid as "one row for each of the 239 countries in
  # country_meta that has a bundled centroid", naming the 10 omissions. Pin the
  # relationship so a data rebuild that adds a centroid fails here and prompts
  # the doc update, rather than silently making the list wrong.
  meta <- countryatlas::country_meta
  tiles <- countryatlas::world_tiles
  has_centroid <- meta$iso3c[!is.na(meta$centroid_lon) & !is.na(meta$centroid_lat)]
  expect_setequal(tiles$iso3c, has_centroid)
  expect_length(setdiff(tiles$iso3c, meta$iso3c), 0L)
  expect_false(any(duplicated(tiles$iso3c)))
  expect_false(any(duplicated(tiles[, c("row", "col")])))   # an equal-area grid
})

# Round-trip and self-consistency invariants for the code tables. Nothing here
# is currently broken -- these exist because a countrycode update or an edit to
# the override table could break any of them silently, and the whole package
# rests on these mappings being coherent.

test_that("codes round-trip through every invertible scheme", {
  all3 <- sort(unique(stats::na.omit(countryatlas::country_meta$iso3c)))
  expect_gt(length(all3), 200L)
  for (sch in list(c("iso2c", "iso2c"), c("country", "country.name"),
                   c("iso3n", "iso3n"))) {
    fwd <- suppressWarnings(convert_country(all3, to = sch[1], from = "iso3c"))
    back <- suppressWarnings(convert_country(fwd, to = "iso3c", from = sch[2]))
    expect_false(anyNA(fwd), info = sch[1])       # every code has a value
    expect_equal(back, all3, info = sch[1])       # and it maps back
  }
})

test_that("the override table is internally consistent", {
  ov <- country_overrides()
  known <- countryatlas:::wdj_known_iso3c()
  expect_gt(length(ov), 0L)
  # Every target is a real code, so an override cannot introduce a phantom one.
  expect_true(all(unname(ov) %in% known))
  # Keys stay plain ASCII by design, so name matching does not depend on the
  # locale (?country_overrides documents this).
  expect_false(any(grepl("[^ -~]", names(ov))))
  # And each key actually resolves to the target it declares.
  expect_equal(unname(suppressWarnings(countryatlas:::wdj_to_iso3c(names(ov)))),
               unname(ov))
})

test_that("every bundled table refers only to known codes", {
  # Enumerated from the package, not listed by hand. The hand-written list was
  # written for 2.0.0 and silently skipped country_groups_history and
  # disputed_territories when 3.0.0 added them -- which is exactly how a new
  # table ends up with no referential check at all. Discovering the tables
  # means the next one is covered the day it lands.
  known <- countryatlas:::wdj_known_iso3c()
  items <- utils::data(package = "countryatlas")$results[, "Item"]
  # `world_snapshot` is a list of frames, so recurse one level.
  seen <- character(0)
  walk <- function(x, nm) {
    if (is.data.frame(x)) {
      if ("iso3c" %in% names(x)) {
        seen <<- c(seen, nm)
        expect_length(
          setdiff(unique(stats::na.omit(x[["iso3c"]])), known), 0L)
      }
    } else if (is.list(x)) {
      for (n in names(x)) walk(x[[n]], paste0(nm, "$", n))
    }
  }
  for (d in items) walk(get(d, envir = asNamespace("countryatlas")), d)
  # Guard the guard: if discovery silently found nothing, the loop above would
  # pass vacuously.
  expect_gte(length(seen), 7L)
  expect_true("country_groups_history" %in% seen)
  expect_true("disputed_territories" %in% seen)
})

# Claims the vignettes make in prose. R CMD check runs their code but never
# checks that the surrounding text is true, so these would drift silently and
# the documentation would start lying to readers.

test_that("README.Rmd's claims hold", {
  # The README is the front page and makes two hard numeric claims, and unlike
  # the vignettes nothing checked either. Its headline figure is computed from
  # a live WDI fetch, so it cannot be pinned offline -- but the *argument* it
  # rests on can be, against the bundled snapshot: joining by plain country
  # name loses dozens of countries, and join_world() loses none.
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  regions <- unique(sub(":.*", "", maps::map("world", plot = FALSE,
                                             fill = TRUE)$names))
  lost_by_name <- sum(!snap$country %in% regions)
  # "42 of 215 countries silently vanish" -- the live figure moves with WDI and
  # with the maps package, so assert the shape of the claim, not the digit.
  expect_gt(lost_by_name, 30)
  expect_lt(lost_by_name, 60)
  expect_equal(nrow(snap), 215)
  # ... and that the package's own join is the fix: every snapshot country
  # carries a code the ISO spine recognises.
  expect_false(anyNA(snap$iso3c))
  expect_length(setdiff(snap$iso3c, countryatlas:::wdj_known_iso3c()), 0L)

  # "Equal-interval breaks put 92% of countries in one class here" -- this one
  # is computed from bundled data, so it is exact.
  mapdf <- suppressWarnings(attach_geometry(snap, geometry = "polygon"))
  tb <- attr(suppressWarnings(classify_compare(mapdf, gdp_per_capita)),
             "countryatlas_classification")
  equal <- tb[tb$method == "equal", ]
  expect_equal(round(100 * max(equal$share)), 92)
  # ... and the contrast it draws with quantiles.
  quant <- tb[tb$method == "quantile", ]
  expect_lt(max(quant$share), 0.25)
})

test_that("the README lists every verb a reader could reach for", {
  # A new export that never makes it into the front page's verb table is
  # invisible to anyone who starts where readers start. Reads README.Rmd, so it
  # needs the source tree.
  skip_if_no_source_tree()
  skip_if_not(file.exists("../../README.Rmd"), "README.Rmd not present")
  rd_txt <- paste(readLines("../../README.Rmd", warn = FALSE), collapse = "\n")
  listed <- gsub("[`()]", "",
                 regmatches(rd_txt,
                            gregexpr("`[a-zA-Z_][a-zA-Z0-9_.]*\\(\\)`",
                                     rd_txt))[[1]])
  ns <- asNamespace("countryatlas")
  fns <- Filter(function(n) is.function(get(n, envir = ns)),
                getNamespaceExports("countryatlas"))
  # The two omissions are deliberate: wdj_overrides() is deprecated, and
  # clear_wdi_cache() is the retained old name for clear_country_cache().
  expect_setequal(setdiff(fns, listed), c("wdj_overrides", "clear_wdi_cache"))
  # And the README names nothing the package does not export.
  expect_length(intersect(listed, fns), length(fns) - 2L)
})

test_that("honest-maps.Rmd's claims hold", {
  # Added for 3.0.0 and, unlike the three older vignettes, never checked. Its
  # island list named the United Kingdom and Indonesia as dropped by contiguity
  # weights when both keep land borders -- a vignette about maps quietly
  # misleading, quietly misleading.
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries

  # "projection_info() says what each of the thirteen preserves"
  expect_equal(nrow(projection_info()), 13L)

  # "Equal-interval and pretty breaks put over 90% of countries into a single
  # class"; "Quantiles put roughly 38 countries in each class"
  mapdf <- suppressWarnings(attach_geometry(snap, geometry = "polygon"))
  tb <- attr(suppressWarnings(classify_compare(mapdf, gdp_per_capita)),
             "countryatlas_classification")
  for (m in c("equal", "pretty")) {
    expect_gt(max(tb$share[tb$method == m]), 0.9)
  }
  expect_true(all(abs(tb$n[tb$method == "quantile"] - 38) <= 2))

  # "silently removes a quarter of the countries with data", and the specific
  # countries named.
  skip_if_no_sf_geometry()
  r <- suppressWarnings(morans_i(snap, gdp_per_capita, n_perm = 0))
  share_lost <- r$n_excluded / (r$n + r$n_excluded)
  expect_gt(share_lost, 0.2)
  expect_lt(share_lost, 0.3)
  excluded <- r$excluded[[1]]
  expect_true(all(c("JPN", "AUS", "MDG", "NZL", "PHL", "CUB", "LKA", "ISL")
                  %in% excluded))
  # ... and the two the vignette now explains are *not* dropped.
  expect_false(any(c("GBR", "IDN") %in% excluded))
})

test_that("the vignettes' version and projection lists match the code", {
  # Two lists that drift silently: the ggsql version countryatlas actually
  # enforces, and the projection names sf-and-projections.Rmd enumerates. The
  # vignette said `DRAW spatial` arrived at 0.4.0 while three places in R/ said
  # 0.4.1, which read as a contradiction until the engine and the R package
  # were named separately.
  skip_if_no_source_tree()
  gg <- paste(readLines("../../vignettes/countryatlas-and-ggsql.Rmd",
                        warn = FALSE), collapse = " ")
  src <- paste(readLines("../../R/visualization.R", warn = FALSE),
               collapse = " ")
  # The version interactive_map() actually enforces, and the version the
  # vignette quotes, have to be the same string.
  guard <- "0.4.1"
  expect_true(grepl(paste0('"', guard, '"'), src, fixed = TRUE))
  expect_true(grepl(guard, gg, fixed = TRUE))

  # sf-and-projections.Rmd enumerates every projection by name. [a-z0-9_], not
  # [a-z_]: "eckert4" has a digit in it.
  sfp <- paste(readLines("../../vignettes/sf-and-projections.Rmd",
                         warn = FALSE), collapse = " ")
  named <- unique(gsub('[`"]', "",
                       regmatches(sfp, gregexpr('`"[a-z0-9_]+"`', sfp))[[1]]))
  expect_length(setdiff(projection_info()$projection, named), 0L)
})

test_that("getting-started.Rmd's claims hold", {
  # It said "income is an ordered factor", which it is not -- a plain factor
  # whose levels happen to be in income order, built that way deliberately in
  # data-raw/. The visual claim held either way, so nothing caught it.
  inc <- countryatlas::world_snapshot$countries$income
  expect_s3_class(inc, "factor")
  expect_false(is.ordered(inc))
  expect_equal(levels(inc)[1], "Not classified")
  expect_equal(levels(inc)[nlevels(inc)], "High income")

  # "search the full World Bank catalogue by name -- offline"
  expect_gt(nrow(wdi_search("renewable energy")), 0L)
  expect_named(wdi_search("renewable energy"), c("indicator", "name"))

  # ?world_snapshot's format section: three elements, sf NULL, and the columns
  # it names by hand.
  w <- countryatlas::world_snapshot
  expect_named(w, c("countries", "sf", "year"))
  expect_null(w$sf)
  expect_true(all(c("iso3c", "iso2c", "country", "gdp_per_capita", "population",
                    "life_expectancy", "co2_per_capita") %in% names(w$countries)))
})

test_that("joining-your-own-data.Rmd's claims hold", {
  # "snaps such points to the nearest country within tolerance_km (25 km by
  # default)"
  expect_equal(formals(locate_country)$tolerance_km, 25)

  # "West Germany is the instructive case: it resolves to DEU and is *not*
  # flagged -- the Federal Republic never dissolved [...] only the entity that
  # actually ceased to exist is flagged."
  d <- suppressWarnings(dissolve_country(c("West Germany", "East Germany"),
                                         warn = FALSE))
  west <- d[d$input == "West Germany", ]
  east <- d[d$input == "East Germany", ]
  expect_equal(west$iso3c, "DEU")
  expect_true(all(is.na(west$historical)))
  expect_equal(east$iso3c, "DEU")
  expect_true(all(!is.na(east$historical)))
  expect_equal(east$dissolved, 1990L)
  m <- suppressWarnings(check_country_match(c("West Germany", "East Germany")))
  expect_equal(m$historical, c(FALSE, TRUE))
})

test_that("the point-lookup example in the vignettes resolves as printed", {
  skip_if_no_sf_geometry()
  # locate_country(lon = c(2.35, -74.0, 139.7), lat = c(48.85, 40.7, 35.7))
  loc <- locate_country(lon = c(2.35, -74.0, 139.7),
                        lat = c(48.85, 40.7, 35.7))
  expect_equal(loc$iso3c, c("FRA", "USA", "JPN"))
})

test_that("the row-count and grid-size claims hold", {
  skip_if_not_installed("maps")
  # countryatlas.Rmd: "not ~99,000 polygon rows"
  n <- nrow(attach_geometry(countryatlas::world_snapshot$countries,
                            geometry = "polygon"))
  expect_gt(n, 90000L)
  expect_lt(n, 110000L)
  # beyond-the-choropleth.Rmd: "the bundled grid covers 239 countries -- see
  # ?world_tiles for the ten it omits"
  expect_equal(nrow(countryatlas::world_tiles), 239L)
  expect_equal(nrow(countryatlas::country_meta) -
                 nrow(countryatlas::world_tiles), 10L)
  # beyond-the-choropleth.Rmd names the five countries bubble_map()/spike_map()
  # cannot place: "Hong Kong, Macao, Gibraltar, the British Virgin Islands and
  # Tuvalu". Named in prose, so a centroid-table rebuild must not leave the
  # vignette quietly wrong.
  cent <- world_geometry("centroids", geometry = "polygon")
  snap <- countryatlas::world_snapshot$countries
  lost <- sort(snap$iso3c[!snap$iso3c %in% cent$iso3c &
                            !is.na(snap$population)])
  expect_equal(lost, c("GIB", "HKG", "MAC", "TUV", "VGB"))
  # The vignette source is absent from an installed check directory, where
  # these tests run from countryatlas.Rcheck/tests/.
  skip_if_no_source_tree()
  skip_if_not(file.exists("../../vignettes/beyond-the-choropleth.Rmd"),
              "vignette source not present")
  btc <- paste(readLines("../../vignettes/beyond-the-choropleth.Rmd",
                         warn = FALSE), collapse = " ")
  for (nm in c("Hong Kong", "Macao", "Gibraltar", "British Virgin Islands",
               "Tuvalu")) {
    expect_match(btc, nm, fixed = TRUE)
  }
  expect_match(btc, "five countries with population", fixed = TRUE)
})

test_that("the override table fully covers the polygon backend's names", {
  # The curated table exists mainly to absorb map_data("world") spellings that
  # countrycode drops. Every region the polygon backend carries should therefore
  # resolve to an iso3c -- if the maps package renames one, this is where it
  # shows up, rather than as silently missing countries on a plot.
  skip_if_not_installed("maps")
  poly <- countryatlas:::get_world_polygons()
  expect_true(all(c("region", "iso3c") %in% names(poly)))
  unresolved <- unique(poly$region[is.na(poly$iso3c)])
  expect_equal(unresolved, character(0))
})

test_that("a custom override changes what the sf backend joins", {
  # `overrides =` is a documented argument; the sf backend deliberately bypasses
  # its geometry cache for a non-default table, so a custom entry must actually
  # take effect -- and must not leak into a later default call.
  skip_if_no_sf_geometry()
  geom <- world_geometry("countries", geometry = "sf")
  skip_if(!anyNA(geom$iso3c), "sf source has no unresolved feature to override")
  # Natural Earth carries Somaliland with no ISO code; map it onto Somalia.
  custom <- country_overrides(c(Somaliland = "SOM"))
  d <- data.frame(iso3c = "SOM", v = 1)
  with_default <- sum(!is.na(suppressWarnings(
    attach_geometry(d, geometry = "sf"))$v))
  with_custom <- sum(!is.na(suppressWarnings(
    attach_geometry(d, geometry = "sf", overrides = custom))$v))
  expect_gt(with_custom, with_default)
  # Order independence: the cache must not serve the custom result afterwards.
  again <- sum(!is.na(suppressWarnings(
    attach_geometry(d, geometry = "sf"))$v))
  expect_equal(again, with_default)
})

test_that("?attach_geometry's coverage figures match the backends", {
  # That section tells a reader which countries are missing from the map and
  # what to do about it, so every number in it is a promise. It said Gibraltar,
  # Hong Kong, Macao, Tuvalu and the British Virgin Islands were "in no backend
  # at any scale" -- but the last four are exactly what scale = "medium"
  # rescues, contradicting the sentence before it. (It looks like the no-*tile*
  # list from ?world_tiles, which is the same five names, got copied in.)
  #
  # If this test fails after an rnaturalearthdata update, the help page is what
  # needs changing, not the numbers here.
  skip_if_no_sf_geometry()
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  expect_identical(nrow(snap), 215L)

  carried <- function(g) {
    length(intersect(snap$iso3c, g$iso3c[!is.na(g$iso3c)]))
  }
  poly <- world_geometry("countries", geometry = "polygon")
  sf_s <- world_geometry("countries", geometry = "sf", scale = "small")
  sf_m <- world_geometry("countries", geometry = "sf", scale = "medium")
  expect_identical(carried(poly), 210L)
  expect_identical(carried(sf_s), 169L)
  expect_identical(carried(sf_m), 214L)

  # Gibraltar alone is in none of them.
  absent <- setdiff(snap$iso3c, unique(c(poly$iso3c, sf_s$iso3c, sf_m$iso3c)))
  expect_identical(sort(absent), "GIB")
  # And these four are carried by the medium sf backend and nothing else.
  for (cc in c("HKG", "MAC", "TUV", "VGB")) {
    expect_false(cc %in% poly$iso3c, info = cc)
    expect_false(cc %in% sf_s$iso3c, info = cc)
    expect_true(cc %in% sf_m$iso3c, info = cc)
  }
})

test_that("the bundled tables are referentially consistent", {
  cm <- countryatlas::country_meta
  wt <- countryatlas::world_tiles
  cg <- countryatlas::country_groups_tbl
  hc <- countryatlas::historical_codes
  ws <- countryatlas::world_snapshot$countries
  valid <- countryatlas:::wdj_known_iso3c()

  # Every code in every table is one the package recognises.
  for (nm in c("country_meta", "world_tiles", "country_groups_tbl",
               "historical_codes", "world_snapshot")) {
    codes <- switch(nm, country_meta = cm$iso3c, world_tiles = wt$iso3c,
                    country_groups_tbl = cg$iso3c, historical_codes = hc$iso3c,
                    world_snapshot = ws$iso3c)
    expect_identical(setdiff(codes, valid), character(0), info = nm)
  }

  # country_meta is the spine: everything else is a subset of it, except the
  # historical successors, which include Kosovo -- countrycode has no XKX row,
  # so neither does country_meta. That gap is documented on ?country_meta and
  # ?distance_between.
  expect_identical(setdiff(wt$iso3c, cm$iso3c), character(0))
  expect_identical(setdiff(ws$iso3c, cm$iso3c), character(0))
  expect_identical(setdiff(cg$iso3c, cm$iso3c), character(0))
  expect_identical(setdiff(hc$iso3c, cm$iso3c), "XKX")

  # Names agree with country_meta wherever the table is built from it...
  same_names <- function(a, b) {
    j <- merge(a, unique(b), by = "iso3c", suffixes = c("_x", "_y"))
    expect_gt(nrow(j), 100L)
    expect_identical(j$country_x, j$country_y)
  }
  same_names(cm[, c("iso3c", "country")], wt[, c("iso3c", "country")])
  same_names(cm[, c("iso3c", "country")], cg[, c("iso3c", "country")])

  # ...but world_snapshot carries the World Bank's names, which differ for 38 of
  # its 215 countries ("Korea, Rep." vs "South Korea"). Both help pages say so;
  # if this count moves, they need updating.
  j <- merge(cm[, c("iso3c", "country")], ws[, c("iso3c", "country")],
             by = "iso3c", suffixes = c("_meta", "_snap"))
  expect_identical(nrow(j), 215L)
  expect_identical(sum(j$country_meta != j$country_snap), 38L)
  expect_identical(j$country_snap[j$iso3c == "KOR"], "Korea, Rep.")
  expect_identical(j$country_meta[j$iso3c == "KOR"], "South Korea")
})

test_that("no documented indicator code has been retired upstream", {
  # The World Bank retires series: EN.ATM.CO2E.KT and EN.ATM.CO2E.PC were
  # replaced by the AR5 greenhouse-gas series, and `?country_data`'s example went
  # on quoting the dead one, so anyone copying it got a warning and an all-NA
  # column. R CMD check reports examples "OK" without failing on warnings, so
  # nothing surfaced it. This is a static check -- every indicator code quoted
  # anywhere in the package must be one the bundled table vouches for.
  skip_if_no_source_tree()
  where <- c(list.files("../../R", pattern = "[.]R$", full.names = TRUE),
             list.files("../../man", pattern = "[.]Rd$", full.names = TRUE),
             list.files("../../vignettes", pattern = "[.]Rmd$", full.names = TRUE))
  where <- where[file.exists(where)]
  txt <- unlist(lapply(where, readLines, warn = FALSE))
  quoted <- unique(unlist(regmatches(
    txt, gregexpr('"[A-Z]{2}\\.[A-Z0-9.]{4,}"', txt))))
  quoted <- gsub('"', "", quoted)
  # Five today: the two AR5 CO2 series, NY.GDP.PCAP.KD, SP.DYN.LE00.IN and
  # SP.POP.TOTL. The other fifteen bundled codes live in data-raw/, which does
  # not ship. Assert the sweep found something rather than pinning the count.
  expect_gte(length(quoted), 3L)

  bundled <- countryatlas::common_indicators$code
  expect_identical(setdiff(quoted, bundled), character(0))
})

test_that("group memberships reflect the accessions the table is dated for", {
  # country_groups_tbl is hand-curated and carries an `as_of` stamp, so it can
  # drift silently: the stamp said 2026-06-01 while the lists still had Sweden
  # outside NATO (acceded 7 March 2024), Angola inside OPEC (left 1 January
  # 2024), BRICS at its original five (expanded January 2024 and again in
  # January 2025) and The Gambia outside the Commonwealth (rejoined 2018).
  # These pin the changes so a rebuild cannot quietly revert them.
  g <- countryatlas::country_groups_tbl
  members <- function(grp) sort(g$iso3c[g$group == grp])

  expect_true("SWE" %in% members("NATO"))        # 7 March 2024
  expect_true("FIN" %in% members("NATO"))        # 4 April 2023
  expect_length(members("NATO"), 32L)

  expect_false("AGO" %in% members("OPEC"))       # left 1 January 2024
  expect_length(members("OPEC"), 12L)

  # BRICS: the original five plus the 2024 intake and Indonesia (January 2025).
  expect_true(all(c("BRA", "RUS", "IND", "CHN", "ZAF") %in% members("BRICS")))
  expect_true(all(c("EGY", "ETH", "IRN", "ARE", "IDN") %in% members("BRICS")))
  # Saudi Arabia was invited in the same round but never confirmed accession.
  expect_false("SAU" %in% members("BRICS"))

  expect_true("GMB" %in% members("Commonwealth"))  # rejoined 2018
  expect_length(members("Commonwealth"), 56L)

  # Unchanged reference points, so a bad rebuild shows up as more than a shift.
  expect_length(members("EU"), 27L)               # post-Brexit
  expect_length(members("EuroZone"), 20L)         # Croatia joined 2023
  expect_length(members("OECD"), 38L)             # Costa Rica joined 2021
  expect_length(members("G7"), 7L)
  expect_false("GBR" %in% members("EU"))
})
