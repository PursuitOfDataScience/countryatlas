# Ternary choropleths (R/map-ternary.R).

tern_fixture <- function(seed = 1) {
  set.seed(seed)
  d <- snap
  d$a <- stats::runif(nrow(d), 1, 4)
  d$b <- stats::runif(nrow(d), 2, 6)
  d$c <- stats::runif(nrow(d), 4, 9)
  d
}

hcl_of <- function(col) {
  methods::as(colorspace::hex2RGB(col), "polarLUV")@coords
}

test_that("the balance scheme puts grey at the barycentre and the primaries at the vertices", {
  skip_if_not_installed("colorspace")
  tc <- countryatlas:::ternary_colours
  P <- rbind(c(1, 1, 1) / 3, diag(3))
  hcl <- hcl_of(tc(P, hue = 80))
  # Equal shares: no chroma, and the lightest colour of the four.
  expect_lt(hcl[1, "C"], 1)
  expect_gt(hcl[1, "L"], max(hcl[-1, "L"]))
  # The vertices: three hues, 120 degrees apart, starting at `hue`. fixup
  # clips an out-of-gamut chroma, which moves a hue by a few degrees.
  h <- hcl[-1, "H"]
  d <- (h - c(80, 200, 320) + 180) %% 360 - 180
  expect_true(all(abs(d) < 12))
  # A composition is a closed vector: scaling every part leaves the colour.
  Q <- rbind(c(0.2, 0.3, 0.5), c(2, 3, 5) / 10)
  expect_identical(tc(Q, 80)[1], tc(Q, 80)[2])
  # Permuting the parts and turning the wheel by a third are the same map.
  R <- matrix(stats::runif(30), 10)
  R <- R / rowSums(R)
  expect_identical(tc(R[, c(3, 1, 2)], 80), tc(R, 200))
})

test_that("centring moves the average composition to grey", {
  tp <- countryatlas:::ternary_perturb
  cen <- c(0.1, 0.3, 0.6)
  expect_equal(unname(tp(rbind(cen), cen)), rbind(rep(1 / 3, 3)))
  P <- rbind(c(0.2, 0.3, 0.5), c(0.05, 0.25, 0.7))
  Q <- tp(P, cen)
  expect_equal(rowSums(Q), c(1, 1))
  # Perturbation by the inverse centre, closed (Aitchison's perturbation).
  expect_equal(Q[1, ], (P[1, ] / cen) / sum(P[1, ] / cen))
})

test_that("ternary_map() draws silently, centred on the average country", {
  skip_slow_on_cran()
  d <- tern_fixture()
  g <- attach_geometry(d)
  expect_silent(p <- ternary_map(g, a, b, c))
  renders(p)
  prov <- attr(p, "countryatlas_provenance")
  # The centre is the closed geometric mean over one row per country, not
  # over the polygon backend's vertex rows.
  P <- as.matrix(d[, c("a", "b", "c")])
  P <- P / rowSums(P)
  gm <- exp(colMeans(log(P)))
  expect_equal(unname(prov$centre), unname(gm / sum(gm)))
  expect_identical(names(prov$centre), c("a", "b", "c"))
  expect_identical(prov$style, "ternary balance, centred")
  expect_match(gg_caption_of(p), "Grey is the average composition: a ")
  # Every country with all three parts has a colour; the count matches the
  # snapshot less the one country no backend can place (Gibraltar).
  expect_identical(prov$coverage$n_shown, nrow(d) - 1L)
  expect_match(map_alt_text(p), "^Ternary choropleth of a, b, c")
  expect_true(any(grepl("ternary balance scheme", map_citation(p), fixed = TRUE)))
  # The plain scheme and a given centre.
  q <- ternary_map(g, a, b, c, centre = FALSE, footnote = FALSE)
  expect_null(attr(q, "countryatlas_provenance")$centre)
  expect_null(gg_caption_of(q))
  r <- ternary_map(g, a, b, c, centre = c(1, 1, 2), key = FALSE)
  expect_equal(unname(attr(r, "countryatlas_provenance")$centre), c(0.25, 0.25, 0.5))
  expect_match(gg_caption_of(r), "Grey is the centre composition")
  renders(r)
})

test_that("ternary_map() treats a country missing a part as no data", {
  skip_slow_on_cran()
  d <- tern_fixture()
  d$a[d$iso3c == "FRA"] <- NA
  d$b[d$iso3c == "DEU"] <- Inf
  d[d$iso3c == "JPN", c("a", "b", "c")] <- 0
  expect_warning(p <- ternary_map(attach_geometry(d), a, b, c),
                 class = "countryatlas_infinite_fill")
  prov <- attr(p, "countryatlas_provenance")
  expect_true(all(c("FRA", "DEU", "JPN") %in% prov$coverage$missing_iso3c))
  # A zero part is a composition (all of it elsewhere), and draws.
  d2 <- tern_fixture()
  d2$a[d2$iso3c == "FRA"] <- 0
  p2 <- ternary_map(attach_geometry(d2), a, b, c)
  expect_false("FRA" %in% attr(p2, "countryatlas_provenance")$coverage$missing_iso3c)
})

test_that("ternary_map() validates its arguments, naming them", {
  skip_slow_on_cran()
  g <- attach_geometry(tern_fixture())
  expect_error(ternary_map(g, a, b), "`z` is required")
  expect_error(ternary_map(g, a, a, c), "three different columns")
  expect_error(ternary_map(g, a, b, nope), "nope")
  expect_error(ternary_map(g, a, b, continent), "must be numeric")
  bad <- g
  bad$a[1] <- -1
  expect_error(ternary_map(bad, a, b, c), class = "countryatlas_negative_part")
  expect_error(ternary_map(g, a, b, c, centre = c(1, 2)), "`centre`")
  expect_error(ternary_map(g, a, b, c, centre = c(1, 0, 2)), "`centre`")
  expect_error(ternary_map(g, a, b, c, centre = NA), "`centre`")
  expect_error(ternary_map(g, a, b, c, hue = 400), "`hue`")
  expect_error(ternary_map(g, a, b, c, key = "yes"), "`key`")
  expect_error(ternary_map(g, a, b, c, legend = c("a", "b")), "`legend`")
  expect_error(ternary_map(g, a, b, c, projection = "nope"), "projection")
  expect_error(ternary_map(tern_fixture(), a, b, c), "no map geometry")
})

test_that("ternary_map() has a defined answer for an empty or zero-only input", {
  skip_slow_on_cran()
  d <- tern_fixture()
  expect_error(ternary_map(attach_geometry(d[0, ]), a, b, c),
               "No country has all three")
  z <- d
  z$a <- 0
  # No country has all three parts above zero: no average to centre on, but
  # the plain scheme still draws.
  expect_error(ternary_map(attach_geometry(z), a, b, c), "no average composition")
  expect_silent(p <- ternary_map(attach_geometry(z), a, b, c, centre = FALSE))
  renders(p)
})

test_that("ternary_map() warns on a panel, like world_map()", {
  skip_slow_on_cran()
  d <- tern_fixture()
  two <- rbind(transform(d, year = 2023L), transform(d, year = 2024L))
  expect_warning(ternary_map(attach_geometry(two), a, b, c),
                 class = "countryatlas_panel")
})

test_that("ternary_map() draws on the sf backend, small states as points", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  d <- tern_fixture()
  p <- ternary_map(attach_geometry(d, geometry = "sf"), a, b, c,
                   projection = "robinson")
  renders(p)
  prov <- attr(p, "countryatlas_provenance")
  expect_identical(prov$backend, "sf")
  expect_gt(prov$n_points, 0L)
  expect_match(gg_caption_of(p), "drawn as points")
})
