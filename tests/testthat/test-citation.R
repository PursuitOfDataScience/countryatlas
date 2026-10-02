# Citations for a map (R/citation.R).

test_that("map_citation() cites the data, geometry, projection and method used", {
  skip_slow_on_cran()
  p <- world_map(poly_df(), gdp_per_capita)
  txt <- map_citation(p)
  expect_type(txt, "character")
  expect_true(any(grepl("World Bank WDI", txt, fixed = TRUE)))
  expect_true(any(grepl("NY.GDP.PCAP.KD", txt, fixed = TRUE)))
  expect_true(any(grepl("Natural Earth", txt, fixed = TRUE)))
  expect_true(any(grepl("Equal Earth", txt, fixed = TRUE)))
  expect_true(any(grepl("Brewer", txt, fixed = TRUE)))        # quantiles
  # A dollar sign in a series name survives the LaTeX formatter.
  expect_true(any(grepl("US$", txt, fixed = TRUE)))
  bib <- map_citation(p, "bibtex")
  expect_s3_class(bib, "Bibtex")
  # Only what the map used: an unprojected continuous map cites neither.
  q <- world_map(poly_df(), gdp_per_capita, style = "continuous", projection = "none")
  qt <- map_citation(q)
  expect_false(any(grepl("Equal Earth", qt, fixed = TRUE)))
  expect_false(any(grepl("Brewer", qt, fixed = TRUE)))
  # Value-by-alpha cites Roth et al.
  v <- value_by_alpha_map(poly_df(), gdp_per_capita, population)
  expect_true(any(grepl("Roth", map_citation(v), fixed = TRUE)))
  expect_error(map_citation(1), "map")
})

test_that("a false-discovery-rate LISA map cites its method", {
  skip_slow_on_cran()
  l <- suppressWarnings(lisa_map(poly_df(), gdp_per_capita, n_perm = 99))
  txt <- map_citation(l)
  expect_true(any(grepl("Caldas de Castro", txt, fixed = TRUE)))
  expect_true(any(grepl("Anselin", txt, fixed = TRUE)))
})

test_that("inst/CITATION carries the 4.0.0 methods", {
  f <- system.file("CITATION", package = "countryatlas")
  skip_if(!nzchar(f), "CITATION not found")
  cit <- utils::readCitationFile(f, meta = list(Encoding = "UTF-8",
                                                Version = "4.0.0"))
  titles <- vapply(unclass(cit), function(e) e$title, "")
  for (t in c("Value-suppressing uncertainty palettes",
              "Funnel plots for comparing institutional performance",
              "A revised list of independent states since the congress of Vienna",
              "The centered ternary balance scheme")) {
    expect_true(any(grepl(t, titles, fixed = TRUE)), info = t)
  }
})
