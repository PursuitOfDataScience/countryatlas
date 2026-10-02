# --- networks --------------------------------------------------------------------

test_that("flow_matrix accumulates repeated pairs", {
  od <- data.frame(from = c("China", "China"), to = c("USA", "USA"),
                   value = c(300, 200))
  m <- flow_matrix(od, from, to, value)
  expect_equal(unname(m["CHN", "USA"]), 500)
  expect_equal(unname(m["USA", "CHN"]), 0)
  ms <- flow_matrix(od, from, to, value, symmetric = TRUE)
  expect_equal(unname(ms["USA", "CHN"]), 500)
})

test_that("flow_matrix warns about endpoints it cannot resolve", {
  skip_slow_on_cran()
  od <- data.frame(from = c("China", "Wakanda"), to = c("USA", "USA"),
                   value = c(1, 2))
  expect_warning(m <- flow_matrix(od, from, to, value), "did not resolve")
  expect_equal(nrow(m), 2L)
  expect_error(
    suppressWarnings(flow_matrix(data.frame(from = "Wakanda", to = "Atlantis"),
                                 from, to)),
    "No usable flows left")
  # An unusable *weight* is a different failure from an unresolvable country,
  # and must not be reported as one.
  expect_warning(
    flow_matrix(data.frame(from = c("United States", "China"),
                           to = c("China", "Japan"), value = c(NA_real_, 5)),
                from, to, value),
    "weight is missing or infinite")
})

test_that("country_network summarises nodes and edges", {
  od <- data.frame(from = c("China", "China", "USA", "Mexico"),
                   to = c("USA", "Germany", "Mexico", "USA"),
                   value = c(500, 100, 300, 320))
  n <- country_network(od, from, to, value)
  expect_named(n, c("nodes", "edges"))
  expect_true(all(c("out_flow", "in_flow", "net_flow", "strength_share") %in%
                    names(n$nodes)))
  chn <- n$nodes[n$nodes$iso3c == "CHN", ]
  expect_equal(chn$out_flow, 600)
  expect_equal(chn$in_flow, 0)
  # USA <-> Mexico is reciprocal; China -> Germany is not.
  usa_mex <- n$edges[n$edges$from == "USA" & n$edges$to == "MEX", ]
  expect_equal(usa_mex$reciprocity, 320 / 300, tolerance = 1e-9)
})

test_that("od_map draws one panel per origin", {
  skip_slow_on_cran()
  od <- data.frame(from = rep(c("China", "Germany", "USA"), each = 3),
                   to = c("USA", "Japan", "Brazil", "France", "Italy", "Poland",
                          "Mexico", "Canada", "Japan"),
                   value = c(500, 200, 90, 80, 70, 60, 300, 280, 120))
  p <- od_map(od, from, to, value, origins = 3)
  renders(p)
  expect_equal(length(unique(ggplot2::ggplot_build(p)$data[[1]]$PANEL)), 3L)
  renders(od_map(od, from, to, value, origins = c("China", "USA")))
  renders(od_map(od, from, to, value, origins = 2, direction = "in"))
  expect_error(od_map(od, from, to, value, origins = "Wakanda"), "did not resolve")
})

test_that("flow_matrix fill applies only to pairs with no flow", {
  # `fill` is documented as the value for pairs with no flow, but the matrix was
  # initialised to it and the weights accumulated on top, so fill = -1 turned a
  # flow of 10 into 9 -- and symmetric = TRUE doubled the fill on top of that.
  od <- data.frame(from = c("France", "Germany", "France"),
                   to   = c("Germany", "Italy", "Germany"),
                   w    = c(10, 20, 5))
  m <- flow_matrix(od, from, to, w, fill = -1)
  expect_equal(m["FRA", "DEU"], 15)   # accumulated, not 14
  expect_equal(m["DEU", "ITA"], 20)
  expect_equal(m["FRA", "ITA"], -1)   # genuinely absent
  # The default is unchanged.
  m0 <- flow_matrix(od, from, to, w)
  expect_equal(unname(m0[c("FRA", "DEU"), c("DEU", "ITA")][1, 1]), 15)
  expect_equal(m0["FRA", "ITA"], 0)
  # Symmetrising must not add the fill to itself.
  ms <- flow_matrix(od, from, to, w, symmetric = TRUE, fill = -1)
  expect_equal(ms["FRA", "DEU"], 15)
  expect_equal(ms["DEU", "FRA"], 15)
  expect_equal(ms["FRA", "ITA"], -1)
})

test_that("od_map says when a named origin sends no flow", {
  skip_slow_on_cran()
  # Italy appears only as a destination, so it has nothing to draw. Filtering
  # the top-N list silently is what "top N" means; dropping an origin the
  # caller named by hand is not.
  od <- data.frame(from = c("France", "France"),
                   to   = c("Germany", "Italy"), w = c(10, 20))
  expect_warning(od_map(od, from, to, w, origins = c("France", "Italy")),
                 "named origin")
  expect_no_warning(od_map(od, from, to, w, origins = 6))
  # Nothing left to draw is still an error, not an empty plot.
  only_in <- data.frame(from = "France", to = "Germany", w = 1)
  expect_error(suppressWarnings(od_map(only_in, from, to, w,
                                       origins = "Germany")),
               "None of the chosen origins")
})

test_that("country_network checks top_n before building the network", {
  d <- data.frame(o = c("France", "Germany"), d = c("Germany", "France"),
                  w = c(1, 2))
  # It used to build the matrix, node table and sorted edge list first.
  expect_error(country_network(d, o, d, w, top_n = "x"), "`top_n`")
  expect_error(country_network(d, o, d, w, top_n = -1), "`top_n`")
  net <- country_network(d, o, d, w, top_n = 1)
  expect_equal(nrow(net$edges), 1L)
  expect_named(net, c("nodes", "edges"))
})

test_that("od_map() draws a repeated origin once", {
  skip_slow_on_cran()
  od <- data.frame(from = rep(c("China", "Germany"), each = 2),
                   to = c("United States", "Japan", "France", "Italy"),
                   value = c(5, 2, 3, 1))
  p <- od_map(od, from, to, value, origins = c("China", "China"))
  expect_equal(levels(countryatlas:::gg_plot_data(p)$.wdj_panel), "China")
})

test_that("od_map() names a destination the basemap cannot draw", {
  skip_slow_on_cran()
  # Gibraltar has no polygon at 1:50m (Hong Kong, the 3.0.0 example, has one
  # on the Natural Earth basemap).
  od <- data.frame(from = "Spain", to = c("Gibraltar", "France", "Italy"),
                   value = c(900, 500, 200))
  expect_warning(p <- od_map(od, from, to, value, origins = 1),
                 class = "countryatlas_no_geometry")
  expect_warning(od_map(od, from, to, value, origins = 1), "GIB")
  # Every destination drawable: nothing to say.
  ok <- od[od$to != "Gibraltar", ]
  expect_no_warning(od_map(ok, from, to, value, origins = 1),
                    class = "countryatlas_no_geometry")
})
