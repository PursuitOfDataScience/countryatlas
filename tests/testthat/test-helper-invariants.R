# Cross-verb invariants for the shared helpers.
#
# Four of the "exhaustive audit" claims in NEWS.md turned out to be incomplete,
# and in every case the miss was the same shape: a code path that BYPASSES the
# shared helper the audit reasoned about. compute_breaks() for `n_bins` (the
# tmap engine returned before any check), wdj_to_iso3c() for country keys,
# ascii_lower() for case folding, wdj_return_frame() for the return class.
#
# A per-verb test cannot catch that, because the verb passes its own test with
# its own bypass in place. These assert the invariant across the whole verb set
# instead, and they are behavioural rather than grep-based on purpose: a verb
# that inlines the helper's logic correctly should pass, and one that reaches
# the same place by a different route should still be caught.

test_that("every verb taking `origin` resolves the same awkward names", {
  # NFD accents and a non-breaking space are the two forms that reach a package
  # from a spreadsheet or a web table, and wdj_to_iso3c() handles both -- an
  # NFD second pass that strips combining marks, and a Unicode-aware trim. A
  # verb that calls countrycode() directly gets neither, and drops the country
  # in silence.
  #
  # Built with intToUtf8(): R/ and tests/ are pure ASCII by convention.
  nfd <- intToUtf8(c(67, 111, 770, 116, 101, 32, 100, 39, 73, 118, 111, 105,
                     114, 101))                      # "Cote d'Ivoire", NFD
  nbsp <- intToUtf8(c(160, 70, 114, 97, 110, 99, 101, 160))  # nbsp France nbsp
  plain <- "France"

  # Verbs whose first argument is a country vector and which take `origin`.
  # Each returns something from which the resolved code is readable.
  code_of <- list(
    check_country_match = function(x) {
      out <- check_country_match(x)
      out$iso3c[1]
    },
    repair_country_names = function(x) {
      suppressMessages(wdj_to_iso3c(repair_country_names(x)))[1]
    },
    country_timeline = function(x) {
      out <- suppressWarnings(country_timeline(x))
      if (!nrow(out)) NA_character_ else out$iso3c[1]
    },
    in_group = function(x) {
      # in_group() reports membership, so read it against a group the country
      # is in: resolution failing shows up as FALSE.
      if (isTRUE(in_group(x, "EU")) || isTRUE(in_group(x, "G20"))) "resolved"
        else NA_character_
    },
    neighbors = function(x) {
      out <- suppressWarnings(suppressMessages(neighbors(x)))
      if (!nrow(out)) NA_character_ else out$iso3c[1]
    }
  )

  for (nm in names(code_of)) {
    f <- code_of[[nm]]
    base <- suppressWarnings(f(plain))
    # The plain name must resolve, or the probe itself is wrong.
    expect_false(is.na(base), label = paste(nm, "resolves", plain))
    # A non-breaking space either side must not change the answer.
    expect_identical(suppressWarnings(f(nbsp)), base,
                     label = paste(nm, "resolves a nbsp-padded name"))
  }

  # The NFD case needs a country whose name carries an accent, so it is checked
  # against the same verbs with a different reference value.
  for (nm in names(code_of)) {
    f <- code_of[[nm]]
    nfc <- suppressWarnings(f(intToUtf8(c(67, 244, 116, 101, 32, 100, 39, 73,
                                          118, 111, 105, 114, 101))))
    expect_identical(suppressWarnings(f(nfd)), nfc,
                     label = paste(nm, "reads NFD and NFC alike"))
  }
})

test_that("`n_bins` changes the output of every verb that takes it", {
  # world_map(engine = "tmap") accepted n_bins, returned before compute_breaks()
  # ever ran, and drew tmap's own default bin count -- while the audit that
  # declared n_bins handled had reasoned about compute_breaks(). Assert the
  # observable effect per verb instead of the call.
  skip_if_no_sf_geometry()
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  poly <- suppressMessages(attach_geometry(snap, geometry = "polygon"))
  sfd <- suppressMessages(attach_geometry(snap, geometry = "sf"))

  # How many classes the map actually draws. The binning lives in one of two
  # places depending on style: `style = "quantile"`/`"jenks"` cut the column
  # into `.wdj_bin` ahead of the scale, while `style = "binned"` hands the
  # break points to ggplot2's own binned scale and adds no column. Read
  # whichever exists, so the invariant holds across styles rather than
  # accidentally testing only one.
  n_levels <- function(p) {
    d <- p$data
    col <- intersect(c(".wdj_bin", ".wdj_vsup"), names(d))
    if (length(col)) {
      return(length(levels(droplevels(factor(d[[col]])))))
    }
    fill_scale <- Filter(function(s) "fill" %in% s$aesthetics, p$scales$scales)
    if (!length(fill_scale)) return(NA_integer_)
    length(unlist(fill_scale[[1]]$breaks))
  }

  # ggplot2 engine, binned styles.
  for (style in c("quantile", "binned")) {
    a <- suppressWarnings(suppressMessages(
      world_map(poly, gdp_per_capita, style = style, n_bins = 3)))
    b <- suppressWarnings(suppressMessages(
      world_map(poly, gdp_per_capita, style = style, n_bins = 7)))
    expect_false(identical(n_levels(a), n_levels(b)),
                 label = paste("world_map style =", style, "honours n_bins"))
  }

  # The provenance records it for every engine, which is what a caller reads.
  for (n in c(3L, 7L)) {
    p <- suppressWarnings(suppressMessages(
      world_map(poly, gdp_per_capita, style = "quantile", n_bins = n)))
    expect_equal(map_provenance(p)$n_bins, n)
  }
  if (requireNamespace("tmap", quietly = TRUE)) {
    for (n in c(3L, 7L)) {
      p <- suppressWarnings(suppressMessages(
        world_map(sfd, gdp_per_capita, engine = "tmap", n_bins = n)))
      expect_equal(map_provenance(p)$n_bins, n)
    }
  }

  # globe_map and value_by_alpha_map take it too.
  g3 <- suppressWarnings(suppressMessages(
    globe_map(sfd, gdp_per_capita, style = "quantile", n_bins = 3)))
  g7 <- suppressWarnings(suppressMessages(
    globe_map(sfd, gdp_per_capita, style = "quantile", n_bins = 7)))
  expect_false(identical(n_levels(g3), n_levels(g7)))

  set.seed(1)
  unc <- abs(stats::rnorm(nrow(sfd))) + 1
  v3 <- suppressWarnings(suppressMessages(
    value_by_alpha_map(cbind(sfd, se = unc), gdp_per_capita, se, n_bins = 3)))
  v7 <- suppressWarnings(suppressMessages(
    value_by_alpha_map(cbind(sfd, se = unc), gdp_per_capita, se, n_bins = 7)))
  expect_false(identical(n_levels(v3), n_levels(v7)))

  # world_query emits it as text.
  expect_match(world_query(value, layer = "binned", n_bins = 3),
               "BIN fill INTO 3")
  expect_match(world_query(value, layer = "binned", n_bins = 7),
               "BIN fill INTO 7")
})

test_that("every column-adding verb honours wdj_return_frame's contract", {
  # The contract, stated on wdj_return_frame() itself: an `sf` frame keeps its
  # class -- the map verbs require it, and losing it while the geometry column
  # survived is what made `join_world(geometry = "sf") |> share_of_world() |>
  # world_map()` die on "`data` has no map geometry" -- and everything else
  # normalises to a tibble. Grouping is dropped, and no internal `.wdj_*` key
  # may leak.
  #
  # A verb that does its own column surgery at the end, or ungroups by hand,
  # bypasses the helper: that is how the temporary `.wdj_unit` key leaked out
  # of two verbs. Assert it across the whole set rather than per verb.
  panel <- data.frame(
    iso3c = rep(c("USA", "FRA", "CHN"), each = 3),
    year = rep(2000:2002, 3),
    v = c(1, 2, 3, 10, 20, 30, 100, 150, 200),
    population = 1e6, ppp = 2, defl = rep(c(1, 1.02, 1.05), 3),
    stringsAsFactors = FALSE
  )
  verbs <- list(
    per_capita = function(d) per_capita(d, v, pop = population),
    share_of_world = function(d) share_of_world(d, v),
    rank_countries = function(d) rank_countries(d, v),
    growth_rate = function(d) growth_rate(d, v),
    index_to = function(d) index_to(d, v, base_year = 2000),
    lag_by_country = function(d) lag_by_country(d, v),
    diff_by_country = function(d) diff_by_country(d, v),
    smooth_rates = function(d) smooth_rates(d, v, population),
    to_ppp = function(d) to_ppp(d, v, factor = ppp),
    deflate = function(d) deflate(d, v, base_year = 2000, deflator = defl),
    interpolate_missing = function(d) interpolate_missing(d, "v")
  )
  for (nm in names(verbs)) {
    f <- verbs[[nm]]
    for (input in list(df = panel, tbl = tibble::as_tibble(panel))) {
      out <- suppressWarnings(suppressMessages(f(input)))
      expect_s3_class(out, "tbl_df")
      expect_false(dplyr::is_grouped_df(out),
                   label = paste(nm, "returns an ungrouped frame"))
      expect_true(all(names(panel) %in% names(out)),
                  label = paste(nm, "keeps the caller's columns"))
      expect_length(grep("^[.]wdj_", names(out)), 0L)
    }
    # A grouped input must not leak its grouping back out.
    grouped <- dplyr::group_by(tibble::as_tibble(panel), .data$iso3c)
    out_g <- suppressWarnings(suppressMessages(f(grouped)))
    expect_false(dplyr::is_grouped_df(out_g),
                 label = paste(nm, "drops the caller's grouping"))
    expect_length(grep("^[.]wdj_", names(out_g)), 0L)
  }

  # And the half that matters most: an `sf` frame keeps its class, so the map
  # verbs still accept the result.
  skip_if_no_sf_geometry()
  sfd <- suppressMessages(attach_geometry(
    data.frame(iso3c = c("FRA", "DEU", "ITA"), v = c(1, 2, 3),
               population = 1e6, ppp = 2, stringsAsFactors = FALSE),
    geometry = "sf"))
  sf_verbs <- list(
    per_capita = function(d) per_capita(d, v, pop = population),
    share_of_world = function(d) share_of_world(d, v),
    rank_countries = function(d) rank_countries(d, v),
    spatial_lag = function(d) spatial_lag(d, v)
  )
  for (nm in names(sf_verbs)) {
    out <- suppressWarnings(suppressMessages(sf_verbs[[nm]](sfd)))
    expect_s3_class(out, "sf")
    expect_false(is.null(attr(out, "sf_column")),
                 label = paste(nm, "keeps an active geometry column"))
    expect_length(grep("^[.]wdj_", names(out)), 0L)
  }
})
