# --- historical crosswalk -------------------------------------------------------

test_that("historical_codes has the expected shape", {
  expect_s3_class(historical_codes, "tbl_df")
  expect_named(historical_codes,
               c("historical", "iso3c_hist", "dissolved", "iso3c", "relation",
                 "country"))
  expect_equal(nrow(historical_codes), 41L)
  expect_false(anyNA(historical_codes$iso3c))
  expect_false(anyNA(historical_codes$country))
  # The headline entities resolve to the right number of successors.
  expect_equal(sum(historical_codes$historical == "Soviet Union"), 15L)
  expect_equal(sum(historical_codes$historical == "Yugoslavia"), 7L)
  expect_equal(sum(historical_codes$historical == "Czechoslovakia"), 2L)
})

# --- time --------------------------------------------------------------------------

test_that("country_groups_history reconciles with the current snapshot", {
  h <- countryatlas::country_groups_history
  expect_true(all(c("group", "iso3c", "country", "from", "to", "status") %in%
                    names(h)))
  expect_false(anyNA(h$from))
  # A country can have several spells in a group, never overlapping ones.
  h2 <- h[order(h$group, h$iso3c, h$from), ]
  same <- h2$group[-1] == h2$group[-nrow(h2)] & h2$iso3c[-1] == h2$iso3c[-nrow(h2)]
  prev_to <- h2$to[-nrow(h2)]
  expect_false(any(same & (is.na(prev_to) | h2$from[-1] < prev_to)))
  expect_true(all(is.na(h$to) | h$to > h$from))
  # Every group's members current today must equal country_groups_tbl.
  today <- Sys.Date()
  cur <- h[h$from <= today & (is.na(h$to) | h$to > today) & h$status == "member", ]
  for (g in unique(h$group)) {
    expect_setequal(
      cur$iso3c[cur$group == g],
      countryatlas::country_groups_tbl$iso3c[
        countryatlas::country_groups_tbl$group == g])
  }
})

# --- disputes, uncertainty, imputation -------------------------------------------

test_that("disputed_territories is scoped and internally consistent", {
  dt <- countryatlas::disputed_territories
  expect_false(any(duplicated(dt$territory)))
  expect_false(anyNA(dt$note))
  expect_true(all(dt$status %in% c("un_member", "un_observer",
                                   "partially_recognised", "administered",
                                   "claimed")))
  # Most disputed territories have no ISO code at all -- that is the point.
  expect_true(sum(is.na(dt$iso3c)) > 0)
  expect_true(all(is.na(dt$iso3c) | dt$iso3c %in% countryatlas:::wdj_known_iso3c()))
})

test_that("disputed_territories' party codes are ISO or a documented placeholder", {
  dt <- countryatlas::disputed_territories
  known <- countryatlas:::wdj_known_iso3c()
  # These columns look like iso3c and mostly are, but six parties are entities
  # ISO gives no code to. Nothing said so, so reading the column as iso3c
  # produced silent NAs. Pin the exact set: a new placeholder must be
  # documented, and a typo in an existing one must fail here.
  placeholders <- c("ABK", "CYP-N", "OST", "PMR", "SAH", "SOL")
  split1 <- function(x) unlist(strsplit(as.character(x), "[;] *"))
  parties <- stats::na.omit(c(split1(dt$administered_by),
                              split1(dt$claimed_by)))
  expect_true(all(parties %in% c(known, placeholders)))
  expect_setequal(setdiff(unique(parties), known), placeholders)
  on <- function(col, code) {
    grepl(paste0("(^|; *)", code, "( *;|$)"), col)
  }
  # Five are self-administering entities ISO codes nowhere: they appear in
  # `administered_by` for the like-named territory, which has no iso3c either.
  for (p in c("ABK", "CYP-N", "OST", "PMR", "SOL")) {
    hit <- on(dt$administered_by, p)
    expect_true(any(hit), label = paste(p, "administers something"))
    expect_true(all(is.na(dt$iso3c[hit])),
                label = paste(p, "administers a row with no iso3c"))
  }
  # SAH is the exception, and the reason a uniform rule cannot be asserted: it
  # is a claimant only, of a territory ISO *does* code.
  expect_false(any(on(dt$administered_by, "SAH")))
  sah <- dt[on(dt$claimed_by, "SAH"), ]
  expect_equal(nrow(sah), 1L)
  expect_equal(sah$territory, "Western Sahara")
  expect_equal(sah$iso3c, "ESH")
  expect_equal(sah$administered_by, "MAR")
  # And they are genuinely not resolvable, which is why they are documented.
  expect_true(all(is.na(suppressWarnings(
    convert_country(placeholders, to = "country", origin = "iso3c",
                    warn = FALSE)))))
})

test_that("country_meta encodes 'unknown' one way", {
  # WDI_data uses "" for an unknown capital and it passed straight through, so
  # five countries had a blank capital alongside 34 NAs -- is.na(capital) was
  # wrong for those five and the factsheet printed "capital: " with nothing
  # after it.
  cm <- countryatlas::country_meta
  for (col in names(cm)[vapply(cm, is.character, logical(1))]) {
    blanks <- sum(!is.na(cm[[col]]) & trimws(cm[[col]]) == "")
    expect_equal(blanks, 0L, info = col)
  }
  expect_true(is.na(cm$capital[cm$iso3c == "HKG"]))
  # countrycode's 249 rows, nothing lost in the rewrite, plus Kosovo's.
  expect_equal(nrow(cm), 250L)
})

test_that("bundled datasets are never referenced bare inside the package", {
  skip_slow_on_cran()
  # A bare `world_tiles` resolves only while the package is *attached*: the
  # lazy-data objects live in the package environment, which is not on a
  # namespace-only lookup path. So `countryatlas::tile_map(...)` in a script with
  # no library() call died with "object 'world_tiles' not found" -- and so did
  # dissolve_country, distance_between, country_groups, in_group and
  # world_geometry(region = <group name>). Every test in this suite attaches the
  # package, so nothing caught it. Declaring the names in globalVariables()
  # silenced the check NOTE without fixing the runtime lookup, which is why the
  # NOTE existed. They must be `countryatlas::`-qualified.
  skip_if_no_source_tree()
  datasets <- c("world_snapshot", "country_meta", "world_tiles",
                "country_groups_tbl", "historical_codes", "common_indicators")
  files <- setdiff(list.files("../../R", pattern = "[.]R$", full.names = TRUE),
                   "../../R/data.R")            # data.R is the roxygen for them

  for (f in files) {
    code <- readLines(f, warn = FALSE)
    code <- code[!grepl("^\\s*#", code)]          # drop comment-only lines
    code <- sub("#.*$", "", code)                 # and trailing comments
    for (d in datasets) {
      # A bare use: the name not preceded by `::` or `$` and not inside a string.
      hits <- grep(paste0("(^|[^\\w.:$\"\'])", d, "([^\\w.\"\']|$)"),
                   code, perl = TRUE, value = TRUE)
      hits <- hits[!grepl(paste0("countryatlas::", d), hits, fixed = TRUE)]
      hits <- hits[!grepl("globalVariables", hits, fixed = TRUE)]
      expect_identical(hits, character(0),
                       info = paste(basename(f), "refers to", d, "unqualified"))
    }
  }
})
