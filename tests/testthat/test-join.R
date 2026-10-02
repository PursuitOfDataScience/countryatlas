test_that("country_join reconciles messy names on both sides", {
  a <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
  b <- data.frame(nation = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  out <- country_join(a, b, country, nation)
  expect_equal(nrow(out), 2)
  expect_true(all(c("gdp", "pop", "iso3c") %in% names(out)))
  expect_equal(out$pop[out$iso3c == "CZE"], 10)
})

test_that("country_join supports inner and full joins", {
  a <- data.frame(c = c("France", "Germany"), x = 1:2)
  b <- data.frame(c = c("Germany", "Japan"), y = 1:2)
  expect_equal(nrow(country_join(a, b, c, c, type = "inner")), 1)
  expect_equal(nrow(country_join(a, b, c, c, type = "full")), 3)
})

test_that("join_world auto-detects the country column", {
  rates <- data.frame(country = c("United States", "Brazil", "Kenya"),
                      v = c(1, 2, 3))
  out <- join_world(rates, geometry = "none", warn = FALSE)
  expect_true("iso3c" %in% names(out))
  expect_equal(sort(out$iso3c), c("BRA", "KEN", "USA"))
})

test_that("attach_geometry bolts polygon geometry onto a country table", {
  df <- data.frame(iso3c = c("USA", "CAN"), value = c(1, 2))
  out <- attach_geometry(df, geometry = "polygon")
  expect_true(all(c("long", "lat", "group", "value") %in% names(out)))
  expect_gt(nrow(out), 100)
  # Geometry is kept for the whole world (context), with values filled where
  # the table has them and NA elsewhere.
  expect_equal(out$value[out$iso3c == "USA"][1], 1)
  expect_true(any(is.na(out$value)))
})

test_that("country_join_all reduce-joins many messy tables on the ISO spine", {
  a <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
  b <- data.frame(country = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  d <- data.frame(country = c("Czechia", "Korea"), area = c(79, 100))
  out <- country_join_all(list(a, b, d), by = "country")
  expect_equal(nrow(out), 2)
  expect_true(all(c("gdp", "pop", "area", "iso3c") %in% names(out)))
  expect_equal(out$pop[out$iso3c == "CZE"], 10)
  expect_equal(out$area[out$iso3c == "KOR"], 100)
})

test_that("country_join_all supports per-table origin specs", {
  a <- data.frame(code = c("CZE", "KOR"), gdp = c(1, 2))
  b <- data.frame(name = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  out <- country_join_all(list(a, b), by = c("code", "name"),
                          origin = c("iso3c", "country.name"))
  expect_equal(nrow(out), 2)
  expect_true(all(c("gdp", "pop") %in% names(out)))
})

test_that("country_join_all supports inner and left joins", {
  a <- data.frame(c = c("France", "Germany"), x = 1:2)
  b <- data.frame(c = c("Germany", "Japan"), y = 1:2)
  expect_equal(nrow(country_join_all(list(a, b), by = "c", type = "inner")), 1)
  expect_equal(nrow(country_join_all(list(a, b), by = "c", type = "left")), 2)
})

test_that("country_join_all errors on bad input", {
  expect_error(country_join_all(list(), by = "x"), class = "countryatlas_error")
  expect_error(
    country_join_all(list(data.frame(a = "France")), by = "missing"),
    class = "countryatlas_error"
  )
})

test_that("country_join_all reduce-joins many messy tables", {
  a <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
  b <- data.frame(country = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  d <- data.frame(country = c("Czechia", "Korea"), area = c(79, 100))
  out <- country_join_all(list(a, b, d), by = "country")
  expect_true(all(c("gdp", "pop", "area", "iso3c") %in% names(out)))
  expect_equal(nrow(out), 2)
  expect_equal(out$area[out$iso3c == "CZE"], 79)
})

# --- the alternate spine and the deprecations ----------------------------------------

test_that("country_join can key on COW/Gleditsch-Ward codes", {
  a <- data.frame(country = c("Czechia", "South Korea"), gdp = 1:2)
  b <- data.frame(nation = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  iso <- country_join(a, b, country, nation)
  expect_true("iso3c" %in% names(iso))
  gw <- country_join(a, b, country, nation, key = "gwn")
  expect_true("gwn" %in% names(gw))
  expect_false("iso3c" %in% names(gw))
  expect_equal(nrow(gw), 2L)
  expect_error(country_join(a, b, country, nation, key = "nope"), "`key`")
})

test_that("the alternate spine warns about the territories it cannot carry", {
  skip_slow_on_cran()
  a <- data.frame(country = "Hong Kong", gdp = 1)
  b <- data.frame(nation = "Hong Kong SAR, China", pop = 7)
  # COW/GW cover sovereign states, so a dependency has no code. A two-sided
  # join warns once per side, and the two must be distinguishable -- they were
  # once the identical sentence twice, with nothing to say which table each
  # referred to.
  w <- character(0)
  withCallingHandlers(country_join(a, b, country, nation, key = "gwn"),
                      warning = function(x) {
                        w <<- c(w, conditionMessage(x))
                        invokeRestart("muffleWarning")
                      })
  expect_length(w, 2L)
  expect_match(w[1], "in .x.")
  expect_match(w[2], "in .y.")
  expect_true(all(grepl("no .*gwn.* code", w)))
})

test_that("country_join_all generalises country_join's key argument too", {
  t1 <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
  t2 <- data.frame(country = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  t3 <- data.frame(country = c("Czechia", "Korea"), area = c(79, 100))
  # It documents itself as "the many-table generalisation of country_join()",
  # so it has to generalise the whole interface, not part of it.
  iso <- country_join_all(list(t1, t2, t3), by = "country")
  expect_true("iso3c" %in% names(iso))
  gw <- country_join_all(list(t1, t2, t3), by = "country", key = "gwn")
  expect_true("gwn" %in% names(gw))
  expect_false("iso3c" %in% names(gw))
  expect_equal(nrow(gw), 2L)
  # Positional calls from before the argument existed are unaffected.
  expect_equal(nrow(country_join_all(list(t1, t2), "country", "country.name",
                                     "full")), 2L)
  expect_error(country_join_all(list(t1, t2), by = "country", key = "nope"),
               "`key`")
})

test_that("an alternate-key multi-table join names which table it lost", {
  h <- list(data.frame(country = "Hong Kong", g = 1),
            data.frame(country = "France", p = 2))
  w <- character(0)
  withCallingHandlers(country_join_all(h, by = "country", key = "gwn"),
                      warning = function(x) {
                        w <<- c(w, conditionMessage(x))
                        invokeRestart("muffleWarning")
                      })
  expect_length(w, 1L)
  expect_match(w[1], "table 1")
})

test_that("country_join reports names that reconcile to nothing", {
  skip_slow_on_cran()
  # Reconciling both sides to a common key is the whole premise, so a name that
  # reconciles to nothing is the failure this verb exists to prevent -- and it
  # was the one join that never said so. wdj_to_key() only speaks up when a
  # name resolves to iso3c but has no COW/GW code, which on the default
  # key = "iso3c" is never.
  a <- tibble::tibble(country = c("France", "Germany", "Freedonia"), x = 1:3)
  b <- tibble::tibble(nation  = c("France", "Italy", "Ruritania"), y = 4:6)

  # Nested, so both warnings are consumed as well as asserted: one per side,
  # and an escaping warning would show up as noise in the suite summary.
  expect_warning(
    expect_warning(country_join(a, b, country, nation), "Freedonia"),
    "Ruritania")
  # Each side is named separately.
  w <- character(0)
  withCallingHandlers(country_join(a, b, country, nation),
                      warning = function(e) {
                        w <<- c(w, conditionMessage(e))
                        invokeRestart("muffleWarning")
                      })
  expect_length(w, 2L)
  expect_true(any(grepl("`x`", w, fixed = TRUE)))
  expect_true(any(grepl("`y`", w, fixed = TRUE)))

  # Opt out, and stay quiet when everything resolves.
  expect_no_warning(country_join(a, b, country, nation, warn = FALSE))
  clean_a <- tibble::tibble(country = "France", x = 1)
  clean_b <- tibble::tibble(nation = "France", y = 2)
  expect_no_warning(country_join(clean_a, clean_b, country, nation))
  # The join itself is unchanged.
  expect_equal(nrow(suppressWarnings(country_join(a, b, country, nation))), 3L)

  # country_join_all reports per table.
  expect_warning(
    expect_warning(country_join_all(list(a, b), by = c("country", "nation")),
                   "Freedonia"),
    "Ruritania")
  expect_no_warning(country_join_all(list(clean_a, clean_b),
                                     by = c("country", "nation")))
})

test_that("country_join says when standardising collapsed two names into one", {
  skip_slow_on_cran()
  # wdj_to_key() maps distinct inputs onto one code -- "France" and "FRANCE ",
  # or "Congo" and "Congo-Kinshasa" -- and the join then multiplies the other
  # side's rows. dplyr does not warn: with unique keys on one side that is an
  # ordinary one-to-many, not the many-to-many it flags. So two rows became
  # three, France appeared twice with different values, and any downstream sum
  # double-counted it, with nothing on screen to say so.
  x <- data.frame(country = c("France", "Germany"), gdp = c(1, 2))
  y <- data.frame(nation = c("France", "FRANCE ", "Germany"), pop = c(10, 11, 20))
  expect_warning(r <- country_join(x, y, country, nation),
                 class = "countryatlas_key_collapse")
  expect_match(
    conditionMessage(tryCatch(country_join(x, y, country, nation),
                              warning = function(w) w)),
    "FRA", fixed = TRUE)
  expect_equal(nrow(r), 3L)                    # the behaviour is unchanged
  expect_silent(country_join(x, y, country, nation, warn = FALSE))

  # A country-by-year panel is a legitimate one-to-many: the same input name
  # maps to the same code and nothing was collapsed, so there is no warning.
  # What remains is the panel rule's note that `x` meets every year.
  pan <- data.frame(nation = rep(c("France", "Germany"), each = 3),
                    year = rep(2018:2020, 2), pop = 1:6)
  expect_no_warning(expect_message(country_join(x, pan, country, nation),
                                   class = "countryatlas_join_broadcast"))
  # Neither is a side whose duplicates were already in the input under one name.
  dup <- data.frame(nation = c("France", "France"), pop = c(1, 2))
  expect_silent(country_join(x, dup, country, nation))

  # country_join_all() carries the same guard, per table.
  expect_warning(
    country_join_all(list(x, y), by = c("country", "nation")),
    class = "countryatlas_key_collapse")
})

test_that('join_world(geometry = "none") still honours region', {
  skip_slow_on_cran()
  d <- data.frame(country = c("France", "Germany", "Brazil", "China"),
                  gdp = 1:4)
  # Same defect as world_data(): the "none" branch returned before any of the
  # geometry arguments were applied.
  all_rows <- join_world(d, country, geometry = "none", warn = FALSE)
  expect_equal(nrow(all_rows), 4L)
  eu <- join_world(d, country, geometry = "none", region = "Europe",
                   warn = FALSE)
  expect_setequal(eu$iso3c, c("FRA", "DEU"))
  expect_setequal(
    join_world(d, country, geometry = "none", region = c("BRA", "CHN"),
               warn = FALSE)$iso3c,
    c("BRA", "CHN"))
  expect_error(
    join_world(d, country, geometry = "none", region = c(-10, 35, 30, 60),
               warn = FALSE),
    class = "countryatlas_bbox_without_geometry")
  expect_warning(
    join_world(d, country, geometry = "none", scale = "large", warn = FALSE),
    class = "countryatlas_scale_ignored")
  expect_no_warning(join_world(d, country, geometry = "none", warn = FALSE))
})

test_that("recenter moves the polygon backend instead of being dropped", {
  skip_slow_on_cran()
  # The polygon backend hands back lon/lat vertices, and `recenter` was simply
  # dropped there, so join_world(recenter = 150) returned byte-identical
  # coordinates to recenter = NULL and drew an Atlantic-centred map for someone
  # who had asked for a Pacific-centred one. 3.0.0 said so; the rings are now
  # cut at the new antimeridian, as sf::st_break_antimeridian() does on the
  # other backend.
  # Without the snapshot's own classification columns: join_world() replaces
  # them, and says so when a value changes. That notice is not what this test
  # is about.
  snap <- world_snapshot$countries[, c("iso3c", "country", "gdp_per_capita")]

  for (g in list(join_world(snap, recenter = 150),
                 world_geometry(recenter = 150),
                 attach_geometry(snap, recenter = 150))) {
    expect_gte(min(g$long), -30)
    expect_lte(max(g$long), 330)
  }
  # Nothing was asked for, so nothing moves and nothing is said.
  expect_no_warning(a0 <- join_world(snap, recenter = 0))
  expect_no_warning(b0 <- join_world(snap))
  expect_identical(range(a0$long), range(b0$long))

  # And the sf backend recentres too.
  skip_if_no_sf_geometry()
  expect_no_warning(a <- join_world(snap, geometry = "sf", recenter = 150))
  b <- suppressWarnings(join_world(snap, geometry = "sf"))
  expect_false(isTRUE(all.equal(unname(sf::st_bbox(a)["xmin"]),
                                unname(sf::st_bbox(b)["xmin"]))))
})

test_that("every country-keyed join refuses to match NA to NA", {
  # A source-level invariant: relying on "the polygon backend happens to have no
  # NA keys today" is an upstream data property, not something we control. Read
  # the installed namespace rather than the source tree so this also runs under
  # R CMD check, where R/ is not next to the tests.
  ns <- asNamespace("countryatlas")
  fns <- Filter(is.function, mget(ls(ns, all.names = TRUE), envir = ns,
                                 ifnotfound = list(NULL)))
  src <- vapply(fns, function(f) paste(deparse(f), collapse = " "), character(1))
  rx <- "(left|inner|full|right|semi|anti)_join\\((?:[^()]|\\([^()]*\\))*\\)"
  calls <- unlist(regmatches(src, gregexpr(rx, src, perl = TRUE)))
  keyed <- grep("iso3c|by = by|_iso", calls, value = TRUE)
  expect_gt(length(keyed), 10L)                     # the scan really found them
  # unname(): `keyed` inherits names from the namespace scan, and a named
  # character(0) is not expect_equal() to a bare one.
  expect_equal(unname(grep("na_matches", keyed, value = TRUE, invert = TRUE)),
               character(0))
})

test_that("joining on an existing iso3c column is silent", {
  a <- data.frame(iso3c = c("FRA", "DEU"), gdp = 1:2)
  b <- data.frame(iso3c = c("fra ", "DEU"), pop = 3:4)
  expect_silent(j <- country_join(a, b, iso3c, iso3c, origin_x = "iso3c",
                                  origin_y = "iso3c"))
  expect_equal(j$pop, 3:4)
  expect_silent(country_join_all(list(a, b), by = "iso3c", origin = "iso3c"))
  # A *different* key column is still reported before it is replaced.
  a2 <- data.frame(country = c("France", "Germany"), iso3c = c("x", "y"))
  expect_warning(country_join(a2, b, country, iso3c, origin_y = "iso3c"),
                 class = "countryatlas_key_overwritten")
})

test_that("country_join_all(by = ) names an unquoted column", {
  a <- data.frame(iso3c = "FRA", gdp = 1)
  expect_error(country_join_all(list(a, a), by = iso3c, origin = "iso3c"),
               class = "countryatlas_bare_column")
  expect_error(country_join_all(list(a, a), by = 1),
               class = "countryatlas_error")
})

test_that("join_world() says when it replaces a column of the caller's", {
  skip_slow_on_cran()
  d <- data.frame(country = c("France", "Kenya"), region = c("North", "South"),
                  v = 1:2)
  expect_warning(out <- join_world(d, country, geometry = "none"),
                 class = "countryatlas_unasked_overwrite")
  expect_equal(out$region, c("Europe & Central Asia", "Sub-Saharan Africa"))
  expect_no_warning(join_world(d, country, geometry = "none", warn = FALSE))
  # Replacing a column with the values it already holds is not worth a word.
  # A frame standardised here, not the bundled snapshot: the snapshot's regions
  # are the World Bank's as of its build, and countrycode can move a country.
  std <- standardize_country(d[, c("country", "v")], country, warn = FALSE)
  expect_no_warning(join_world(std, country, geometry = "none"),
                    class = "countryatlas_unasked_overwrite")
})

test_that("join_world auto-detects a code column, and reads it as codes", {
  skip_slow_on_cran()
  # The fallback comment said "the first column that mostly matches ISO codes",
  # but it tested with origin = "country.name", which does not match most
  # alpha-3 codes ("FRA" and "JPN" fail; "USA" happens to). And a column named
  # `iso3c` was found by the name list, which set no scheme, so
  # join_world(tibble(iso3c = c("FRA", "JPN"))) warned and returned all NA.
  expect_silent(a <- join_world(tibble::tibble(iso3c = c("FRA", "JPN"), v = 1:2),
                                geometry = "none"))
  expect_identical(a$iso3c, c("FRA", "JPN"))
  expect_silent(b <- join_world(tibble::tibble(code = c("FRA", "JPN"), v = 1:2),
                                geometry = "none"))
  expect_identical(b$iso3c, c("FRA", "JPN"))
  expect_silent(cc <- join_world(tibble::tibble(iso2c = c("FR", "JP"), v = 1:2),
                                 geometry = "none"))
  expect_identical(cc$iso3c, c("FRA", "JPN"))
  # Names still work, including in a column *named* iso3c -- the implied scheme
  # is verified before it is used, so a misnamed column falls back.
  expect_silent(d <- join_world(tibble::tibble(iso3c = c("France", "Japan")),
                                geometry = "none"))
  expect_identical(d$iso3c, c("FRA", "JPN"))
  # An explicit origin is an instruction, not a hint.
  expect_warning(e <- join_world(tibble::tibble(iso3c = c("FRA", "JPN")),
                                 origin = "country.name", geometry = "none"),
                 "could not be matched")
  expect_true(all(is.na(e$iso3c)))
  # And a column that resolves to nothing is still reported, not guessed at.
  expect_error(join_world(tibble::tibble(junk = c("zz", "qq"))),
               "auto-detect")
})

test_that("country_join() joins two panels country-year to country-year", {
  skip_slow_on_cran()
  # Two countries by two years each. Keyed on the country alone this came back
  # as 8 rows with year.x and year.y and no warning: dplyr's many-to-many
  # warning never reaches a join made from package code.
  a <- data.frame(country = rep(c("France", "Germany"), each = 2),
                  year = rep(2019:2020, 2), gdp = 1:4)
  b <- data.frame(nation = rep(c("France", "Germany"), each = 2),
                  year = rep(2019:2020, 2), pop = 5:8)
  expect_message(out <- country_join(a, b, country, nation),
                 class = "countryatlas_join_year")
  expect_equal(nrow(out), 4L)
  expect_false(any(c("year.x", "year.y") %in% names(out)))
  expect_equal(out$pop[out$iso3c == "DEU" & out$year == 2020], 8L)
  # Asking for it is silent; so is naming the column under two names.
  expect_silent(out2 <- country_join(a, b, country, nation, also_by = "year"))
  expect_identical(out2, out)
  b2 <- dplyr::rename(b, yr = year)
  expect_silent(out3 <- country_join(a, b2, country, nation,
                                     also_by = c(year = "yr")))
  expect_equal(out3$pop, out$pop)
  # The way back to a country-only join names what it did.
  expect_warning(cross <- country_join(a, b, country, nation,
                                       also_by = character()),
                 class = "countryatlas_many_to_many")
  expect_equal(nrow(cross), 8L)
  expect_match(conditionMessage(tryCatch(
    country_join(a, b, country, nation, also_by = character()),
    warning = identity)), "FRA", fixed = TRUE)
})

test_that("country_join() broadcasts a cross-section across a panel, and says so", {
  a <- data.frame(country = rep(c("France", "Germany"), each = 2),
                  year = rep(2019:2020, 2), gdp = 1:4)
  cs <- data.frame(nation = c("France", "Germany"), area = c(549, 357))
  expect_message(out <- country_join(a, cs, country, nation),
                 class = "countryatlas_join_broadcast")
  expect_equal(nrow(out), 4L)
  expect_equal(out$area[out$iso3c == "FRA"], c(549, 549))
  # One year is not a panel, so there is nothing to broadcast across.
  expect_silent(country_join(a[a$year == 2019, ], cs, country, nation))
})

test_that("country_join() validates also_by", {
  skip_slow_on_cran()
  a <- data.frame(country = "France", year = 2020L, gdp = 1)
  b <- data.frame(nation = "France", year = 2020L, pop = 2)
  expect_error(country_join(a, b, country, nation, also_by = 1),
               class = "countryatlas_error")
  expect_error(country_join(a, b, country, nation, also_by = NA_character_),
               class = "countryatlas_error")
  expect_error(country_join(a, b, country, nation, also_by = "decade"),
               "does not have")
  expect_error(country_join(a, b, country, nation, also_by = "iso3c"),
               "cannot include")
})

test_that("country_join_all() joins panels on year too, and names a fan-out", {
  skip_slow_on_cran()
  a <- data.frame(country = rep(c("France", "Germany"), each = 2),
                  year = rep(2019:2020, 2), gdp = 1:4)
  b <- data.frame(country = rep(c("France", "Germany"), each = 2),
                  year = rep(2019:2020, 2), pop = 5:8)
  d <- data.frame(country = c("France", "Germany"), area = c(549, 357))
  expect_message(out <- country_join_all(list(a, b, d), by = "country"),
                 class = "countryatlas_join_year")
  expect_equal(nrow(out), 4L)
  expect_equal(out$area[out$iso3c == "FRA"], c(549, 549))
  expect_warning(cross <- country_join_all(list(a, b), by = "country",
                                           also_by = character()),
                 class = "countryatlas_many_to_many")
  expect_equal(nrow(cross), 8L)
  expect_silent(country_join_all(list(a, b), by = "country", also_by = "year"))
  expect_error(country_join_all(list(a, d), by = "country", also_by = "year"),
               "table 2")
  expect_error(country_join_all(list(a, b), by = "country",
                                also_by = c(year = "yr")),
               class = "countryatlas_error")
})

test_that("every internal join declares its cardinality", {
  skip_slow_on_cran()
  # dplyr warns about an unexpected many-to-many join only when the join is
  # made from the console. From package code it says nothing, which is how
  # country_join() multiplied panel rows in silence. A declared relationship
  # turns a violated expectation into an error, so every mutating join in R/
  # has to state one.
  skip_if_no_source_tree()
  joins <- c("left_join", "inner_join", "full_join", "right_join", "join_fun")
  undeclared <- character()
  walk <- function(e, where) {
    if (!is.call(e)) return(invisible())
    fn <- e[[1]]
    nm <- if (is.name(fn)) as.character(fn) else
      if (is.call(fn) && identical(fn[[1]], as.name("::"))) as.character(fn[[3]]) else ""
    if (nm %in% joins && !"relationship" %in% names(e)) {
      undeclared <<- c(undeclared, paste0(where, ": ", deparse(e)[1]))
    }
    for (i in seq_along(e)[-1]) if (is.call(e[[i]])) walk(e[[i]], where)
  }
  for (f in list.files("../../R", pattern = "[.]R$", full.names = TRUE)) {
    for (e in parse(f, keep.source = FALSE)) walk(e, basename(f))
  }
  expect_identical(undeclared, character())
})
