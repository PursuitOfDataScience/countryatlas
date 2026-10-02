test_that("distance_between computes great-circle distance (no sf needed)", {
  d <- distance_between("France", "Germany")
  expect_type(d, "double")
  expect_gt(d, 0)
  # Paris-Berlin ~ 878 km, centroids should be in that ballpark
  expect_gt(d, 500)
  expect_lt(d, 1500)
})

test_that("distance_between recycles vectors", {
  d <- distance_between("USA", c("Canada", "Mexico"))
  expect_length(d, 2)
  expect_true(all(d > 0))
})

test_that("distance_between resolves via iso3c", {
  d1 <- distance_between("France", "Germany")
  d2 <- distance_between("FRA", "DEU", origin = "iso3c")
  expect_equal(d1, d2)
})

test_that("distance_between returns NA for unknown countries", {
  # And says so: a value that resolves to no country is a mistake, unlike a
  # country that resolves but has no bundled centroid, which stays quiet.
  expect_warning(d <- distance_between("France", "Atlantis"),
                 "did not resolve to a country")
  expect_true(is.na(d))
})

test_that("distance_between works on vectors of length 1 (no recycling)", {
  # Identical country -> zero distance
  d <- distance_between("France", "France")
  expect_true(abs(d) < 1e-9)
})

test_that("locate_country tags known capitals", {
  skip_if_no_sf_geometry()
  out <- locate_country(lon = c(2.35, -74.0, 139.7), lat = c(48.85, 40.7, 35.7))
  # Paris, New York, Tokyo
  expect_equal(out$iso3c, c("FRA", "USA", "JPN"))
  expect_equal(out$country, c("France", "United States", "Japan"))
})

test_that("locate_country gives a point the same answer whatever it is with", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  # st_nearest_points()'s pairing argument is `pairwise`; this asked for
  # `by_element`, which sf absorbs into `...` and ignores, so the snap-back
  # step got the length(miss)^2 cross product and measured each unmatched
  # point against some *other* point's country. One missed point was safe
  # (1x1 == pairwise), so every single-point example passed and only
  # multi-point calls were wrong -- in either direction, since a bogus
  # distance under the tolerance would have snapped a point to a country it
  # is not in.
  cm <- countryatlas::country_meta
  cm <- cm[!is.na(cm$centroid_lon) & !is.na(cm$centroid_lat), ]

  batch <- locate_country(cm$centroid_lon, cm$centroid_lat)$iso3c
  alone <- vapply(seq_len(nrow(cm)), function(i) {
    v <- locate_country(cm$centroid_lon[i], cm$centroid_lat[i])$iso3c
    if (length(v) != 1L) NA_character_ else as.character(v)
  }, character(1))
  expect_equal(batch, alone)

  # Cuba is the concrete case: its centroid is ~10.8 km off the 110m
  # coastline, so it always needs the snap. In a multi-miss call it used to be
  # measured against American Samoa and dropped to NA.
  cu <- cm[cm$iso3c == "CUB", ]
  expect_equal(locate_country(cu$centroid_lon, cu$centroid_lat)$iso3c, "CUB")
  expect_equal(batch[cm$iso3c == "CUB"], "CUB")

  # Open ocean must still be NA even in a call where other points miss.
  mixed <- locate_country(c(cu$centroid_lon, 0, -140), c(cu$centroid_lat, 0, 0))
  expect_equal(mixed$iso3c, c("CUB", NA, NA))
})

test_that("locate_country returns NA for open ocean", {
  skip_if_no_sf_geometry()
  out <- locate_country(lon = -30, lat = -30)   # open Atlantic
  expect_true(is.na(out$iso3c))
})

test_that("locate_country supports extra attributes", {
  skip_if_no_sf_geometry()
  out <- locate_country(lon = 2.35, lat = 48.85, add = c("country", "continent"))
  expect_equal(out$country, "France")
  expect_equal(out$continent, "Europe")
})

test_that("locate_country errors on mismatched lon/lat lengths", {
  skip_if_no_sf_geometry()
  expect_error(locate_country(lon = 1:2, lat = 1), class = "countryatlas_error")
})

test_that("locate_country snaps coastal points but leaves open ocean NA", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  # New York sits ~0.5 km outside the coarse 110m US coastline: the default
  # tolerance snaps it to the US, strict mode (tolerance_km = 0) does not.
  expect_equal(locate_country(lon = -74.0, lat = 40.7)$iso3c, "USA")
  expect_true(is.na(locate_country(lon = -74.0, lat = 40.7, tolerance_km = 0)$iso3c))
  # Open ocean is hundreds of km from land, so it stays NA even with snapping.
  expect_true(is.na(locate_country(lon = -30, lat = -30)$iso3c))
})

test_that("country_borders returns a tidy edge list", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  edges <- country_borders()
  expect_s3_class(edges, "tbl_df")
  expect_true(all(c("iso3c_a", "country_a", "iso3c_b", "country_b") %in% names(edges)))
  # France borders Germany
  fra_deu <- dplyr::filter(
    edges,
    (.data$iso3c_a == "FRA" & .data$iso3c_b == "DEU") |
    (.data$iso3c_a == "DEU" & .data$iso3c_b == "FRA")
  )
  expect_equal(nrow(fra_deu), 1)
})

test_that("country_borders never lists a country bordering itself", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  edges <- country_borders()
  expect_false(any(edges$iso3c_a == edges$iso3c_b))
})

test_that("neighbors lists a country's bordering countries", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  nbr <- neighbors("France")
  expect_s3_class(nbr, "tbl_df")
  expect_true("DEU" %in% nbr$neighbor)
  expect_true("ESP" %in% nbr$neighbor)
})

test_that("neighbors returns zero rows for islands", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  nbr <- neighbors("Japan")
  expect_equal(nrow(nbr), 0)
})

test_that("locate_country names Kosovo (XKX has no countrycode row)", {
  skip_if_no_sf_geometry()
  out <- locate_country(lon = 20.9, lat = 42.6, add = c("country", "continent"))
  expect_equal(out$iso3c, "XKX")
  expect_equal(out$country, "Kosovo")
  expect_equal(out$continent, "Europe")
})

test_that("country_borders names every endpoint, Kosovo included", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  edges <- country_borders()
  expect_false(anyNA(edges$country_a))
  expect_false(anyNA(edges$country_b))
  xkx <- edges[edges$iso3c_a == "XKX" | edges$iso3c_b == "XKX", ]
  expect_gt(nrow(xkx), 0)
})

test_that("world_geometry('coastline') works in every projection", {
  skip_slow_on_cran()
  # Two Natural Earth rings are invalid once projected, and st_union() (unlike
  # the predicates) refuses them outright: the coastline used to error with
  # "TopologyException: side location conflict" in all but plate_carree.
  skip_if_no_sf_geometry()
  for (proj in c("equal_earth", "robinson", "mollweide", "mercator",
                 "plate_carree", "orthographic")) {
    cl <- world_geometry("coastline", geometry = "sf", projection = proj)
    # Wrapped in sf as of 2.0.0 (?world_geometry promises an sf object, and
    # st_union() returns a bare sfc); the geometry itself is unchanged.
    expect_s3_class(cl, "sf")
    expect_equal(nrow(cl), 1L)
    expect_equal(as.character(sf::st_geometry_type(cl)[1]), "MULTILINESTRING")
  }
})

test_that("world_geometry accepts a bounding-box region on the sf backend", {
  # Regression: st_crop() under the strict S2 engine rejected Natural Earth's
  # self-intersecting rings, so region = c(xmin, ymin, xmax, ymax) errored.
  skip_if_no_sf_geometry()
  eur <- world_geometry("countries", geometry = "sf",
                        region = c(-10, 35, 30, 60))
  expect_s3_class(eur, "sf")
  expect_gt(nrow(eur), 10)
  expect_lt(nrow(eur), 100)
  expect_true("FRA" %in% eur$iso3c)
  expect_false("AUS" %in% eur$iso3c)
})

test_that("polygon_centroids returns one centroid per iso3c", {
  skip_slow_on_cran()
  # Bug 3.3: PRT / ESP and the other many-piece countries must each produce
  # ONE row, not multiple.
  poly <- countryatlas:::world_polygons()
  cent <- countryatlas:::polygon_centroids(poly)
  # Every iso3c appears exactly once
  expect_equal(anyDuplicated(cent$iso3c), 0)
  # Known multi-piece countries must have exactly one centroid row: France
  # draws with its overseas departments, Indonesia with thousands of islands.
  for (cc in c("PRT", "ESP", "FRA", "IDN")) {
    expect_gt(length(unique(poly$group[poly$iso3c %in% cc])), 1L)
    expect_equal(nrow(dplyr::filter(cent, .data$iso3c == cc)), 1, info = cc)
  }
  # ...on its largest piece: metropolitan France, not French Guiana.
  fra <- cent[cent$iso3c == "FRA", ]
  expect_gt(fra$centroid_lat, 40)
})

test_that("attach_geometry threads custom overrides into geometry matching", {
  skip_slow_on_cran()
  # Regression: world_data(overrides=) / attach_geometry(overrides=) were
  # accepted but silently ignored -- the geometry backend always matched with
  # the default override set. A custom set must now actually take effect.
  poly <- attach_geometry(
    data.frame(iso3c = "ZZ1", value = 42),
    geometry = "polygon",
    overrides = country_overrides(c(Greenland = "ZZ1"))
  )
  # Greenland's polygons carry the custom code and join to the value...
  expect_true(any(poly$iso3c == "ZZ1" & poly$value == 42, na.rm = TRUE))
  # ...and are no longer matched to the default GRL.
  expect_false(any(poly$iso3c == "GRL", na.rm = TRUE))
  # The default path is unaffected (separate cache key): Greenland -> GRL.
  poly_def <- attach_geometry(data.frame(iso3c = "GRL", value = 7),
                              geometry = "polygon")
  expect_true(any(poly_def$iso3c == "GRL", na.rm = TRUE))
})

# ?attach_geometry now documents that the join keeps only countries the chosen
# backend carries, and that the sf `scale` changes coverage and not just detail.
# Pin the properties behind those claims, not the exact counts, which move when
# rnaturalearth updates.

test_that("attach_geometry drops rows the backend has no geometry for", {
  df <- data.frame(iso3c = c("USA", "ZZZ"), value = c(1, 2))
  out <- attach_geometry(df, geometry = "polygon")
  expect_true("USA" %in% out$iso3c)
  expect_false("ZZZ" %in% out$iso3c)      # silent, as documented
  expect_true(all(!is.na(out$long)))
})

test_that("sf coverage is monotone in scale, and medium beats small", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  codes <- function(sc) {
    unique(stats::na.omit(countryatlas:::get_world_sf(scale = sc,
                                                     project = FALSE)$iso3c))
  }
  small <- codes("small")
  medium <- codes("medium")
  # A coarser scale must not carry a country the finer one lacks.
  expect_length(setdiff(small, medium), 0L)
  snap <- unique(stats::na.omit(countryatlas::world_snapshot$countries$iso3c))
  # The documented reason to reach for "medium": it maps materially more of the
  # bundled snapshot than the default "small" does.
  expect_gt(length(intersect(snap, medium)), length(intersect(snap, small)))
})

# world_geometry()'s @return promises an sf object on the sf backend, but
# "coastline" and "ocean" came back as bare sfc (st_union()/st_as_sfc() return
# one), so dplyr verbs failed on exactly those two. Worse, "ocean" was a
# 2-point, zero-area polygon: under the S2 engine -- sf's default since 1.0 --
# st_as_sfc(st_bbox(-180, -90, 180, 90)) collapses, and the collapse is
# invisible because st_bbox() reports the stored extent instead of recomputing
# it. The layer drew nothing, in every projection.

test_that("every what value returns a real sf object", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  for (w in c("countries", "centroids", "coastline", "borders", "graticule",
              "ocean")) {
    o <- world_geometry(w, geometry = "sf")
    expect_s3_class(o, "sf")
    expect_gt(nrow(o), 0L)
    # A bare sfc has no columns for dplyr to work on.
    expect_no_error(dplyr::filter(o, TRUE))
  }
})

test_that("the ocean layer actually covers the map", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  earth <- 5.1e14                                  # m^2, Earth's surface
  for (pr in c("equal_earth", "robinson", "mollweide", "eckert4",
               "gall_peters")) {
    oc <- world_geometry("ocean", geometry = "sf", projection = pr)
    a <- as.numeric(sum(sf::st_area(oc)))
    expect_gt(a, earth * 0.9)                      # was 0, or a few m^2
    expect_lt(a, earth * 1.3)
    # And it sits behind the countries rather than beside them.
    cc <- world_geometry("countries", geometry = "sf", projection = pr)
    covered <- suppressMessages(
      sf::st_covered_by(sf::st_geometry(cc), oc, sparse = FALSE))
    expect_gt(mean(covered), 0.9)
  }
  # The boundary must be densified: four corners give a curved projection
  # nothing to bend, and the result is narrower than the map.
  expect_gt(nrow(sf::st_coordinates(countryatlas:::world_outline())), 100L)
})

test_that("ocean refuses the cases it cannot draw, and says why", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  for (pr in c("orthographic", "azimuthal_equal_area", "north_polar",
               "south_polar")) {
    expect_error(world_geometry("ocean", geometry = "sf", projection = pr),
                 "not available", info = pr)
    expect_error(world_geometry("ocean", geometry = "sf", projection = pr),
                 class = "countryatlas_error")
    # The countries layer itself is fine in these projections.
    expect_s3_class(world_geometry("countries", geometry = "sf",
                                   projection = pr), "sf")
  }
  expect_error(world_geometry("ocean", geometry = "sf", recenter = 150),
               "cannot be recentred")
  expect_s3_class(world_geometry("ocean", geometry = "sf", recenter = 0), "sf")
  # s2 must be left as we found it.
  expect_true(sf::sf_use_s2())
})

test_that("only orthographic drops the far side; the Lambert three keep it", {
  skip_slow_on_cran()
  # ?world_geometry used to call all four azimuthal projections "hemispheric",
  # which is true of "orthographic" (+proj=ortho) alone. The other three are
  # Lambert azimuthal equal-area, which images the whole globe with the far side
  # stretched around the rim -- nothing comes back empty. The docs now say so,
  # and a reader who filters on st_is_empty() depends on the difference.
  skip_if_no_sf_geometry()

  n_empty <- function(projection) {
    g <- world_geometry("countries", geometry = "sf", projection = projection)
    sum(sf::st_is_empty(sf::st_geometry(g)))
  }
  expect_gt(n_empty("orthographic"), 0L)
  for (pr in c("azimuthal_equal_area", "south_polar")) {
    expect_identical(n_empty(pr), 0L, info = pr)
  }
  # Except Antarctica in "north_polar", whose pole is its antipode: its ring
  # closed around the whole map. See clip_for_projection().
  np <- world_geometry("countries", geometry = "sf", projection = "north_polar")
  expect_identical(np$iso3c[sf::st_is_empty(sf::st_geometry(np))], "ATA")
  # Equal-area really is equal-area: New Zealand keeps its size on the far rim.
  nz <- world_geometry("countries", geometry = "sf", projection = "north_polar")
  nz <- nz[!is.na(nz$iso3c) & nz$iso3c == "NZL", ]
  expect_lt(abs(as.numeric(sf::st_area(nz)) / 1e12 - 0.27), 0.15)
})

test_that("the ISO-less Natural Earth features are documented", {
  # ?world_geometry names these as the rows that come back with iso3c NA; if a
  # future rnaturalearth changes the set, the doc has to change with it.
  skip_if_no_sf_geometry()
  g <- world_geometry("countries", geometry = "sf", scale = "small")
  expect_identical(sort(g$name_long[is.na(g$iso3c)]), "Somaliland")
})

test_that("sf centroid columns are projected units, as documented", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  # ?world_geometry now says these are in the returned object's CRS. Pin it, so
  # nobody reads centroid_lon as a longitude by accident.
  s <- world_geometry("centroids", geometry = "sf")
  expect_equal(sf::st_crs(s)$units, "m")
  expect_gt(max(abs(s$centroid_lon), na.rm = TRUE), 1e6)
  # The polygon backend is degrees, and matches country_meta exactly.
  p <- world_geometry("centroids", geometry = "polygon")
  expect_lt(max(abs(p$centroid_lon), na.rm = TRUE), 181)
  m <- merge(p, countryatlas::country_meta[, c("iso3c", "centroid_lon")],
             by = "iso3c", suffixes = c("_geom", "_meta"))
  expect_equal(m$centroid_lon_geom, m$centroid_lon_meta)
})

test_that("no geometry layer is degenerate in any projection", {
  skip_slow_on_cran()
  # The ocean layer was a 2-point, zero-area polygon in every projection, and
  # nothing caught it: st_bbox() reported the stored extent rather than
  # recomputing it, so every diagnostic looked healthy. Measure the geometry
  # itself, for every layer.
  skip_if_no_sf_geometry()
  for (pr in c("equal_earth", "robinson", "mollweide", "plate_carree")) {
    for (w in c("countries", "centroids", "coastline", "borders", "graticule",
                "ocean")) {
      o <- world_geometry(w, geometry = "sf", projection = pr)
      g <- sf::st_geometry(o)
      expect_false(any(sf::st_is_empty(g)), info = paste(pr, w))
      expect_gt(nrow(sf::st_coordinates(g)), 0L)   # needs a homogeneous column
      # A real extent, not a point at the origin.
      expect_gt(as.numeric(diff(sf::st_bbox(g)[c(1, 3)])), 1e6)
      ty <- as.character(sf::st_geometry_type(g)[1])
      if (grepl("POLYGON", ty)) {
        expect_gt(sum(as.numeric(sf::st_area(g))), 0)
      } else if (grepl("LINE", ty)) {
        expect_gt(sum(as.numeric(sf::st_length(g))), 0)
      }
    }
  }
})

test_that("the countries layer is a homogeneous MULTIPOLYGON column", {
  skip_slow_on_cran()
  # Natural Earth hands over 177 uniform MULTIPOLYGONs, but
  # st_break_antimeridian() runs an st_intersection internally that collapses a
  # single-part MULTIPOLYGON to a POLYGON -- leaving 148 POLYGON + 29
  # MULTIPOLYGON, i.e. an sfc_GEOMETRY column. sf::st_coordinates() is not
  # implemented for that, so pulling vertices out of world_geometry("countries")
  # failed, in every projection including the default.
  skip_if_no_sf_geometry()
  for (pr in c("equal_earth", "robinson", "mollweide", "plate_carree")) {
    o <- world_geometry("countries", geometry = "sf", projection = pr)
    expect_equal(unique(as.character(sf::st_geometry_type(o))), "MULTIPOLYGON",
                 info = pr)
    expect_no_error(sf::st_coordinates(o))
    expect_gt(nrow(sf::st_coordinates(o)), 1000L)
  }
  # Region subsets and recentring go through the same path.
  for (o in list(world_geometry("countries", geometry = "sf", recenter = 150),
                 world_geometry("countries", geometry = "sf", region = "Europe"),
                 world_geometry("countries", geometry = "sf",
                                region = c(-10, 35, 30, 60)))) {
    expect_equal(unique(as.character(sf::st_geometry_type(o))), "MULTIPOLYGON")
    expect_no_error(sf::st_coordinates(o))
  }
  # The cast is a type change only: row count and land area are untouched.
  o <- world_geometry("countries", geometry = "sf")
  expect_equal(nrow(o), 177L)
  old <- suppressMessages(sf::sf_use_s2(FALSE))   # NE rings are s2-invalid
  on.exit(suppressMessages(sf::sf_use_s2(old)), add = TRUE)
  land <- sum(as.numeric(sf::st_area(o)))
  expect_gt(land, 1.3e14)                         # Earth land is about 1.48e14
  expect_lt(land, 1.7e14)
})

test_that("a hemispheric projection leaves the far side empty, not malformed", {
  skip_slow_on_cran()
  # Orthographic hides half the globe, so those countries have no image. The
  # empty geometries are correct; recorded here so the resulting
  # st_coordinates() limitation is not mistaken for the bug fixed above.
  skip_if_no_sf_geometry()
  o <- world_geometry("countries", geometry = "sf", projection = "orthographic")
  expect_equal(unique(as.character(sf::st_geometry_type(o))), "MULTIPOLYGON")
  expect_gt(sum(sf::st_is_empty(o)), 0L)
  expect_lt(sum(sf::st_is_empty(o)), nrow(o))
  # Dropping the empties gives a column st_coordinates() can read.
  vis <- o[!sf::st_is_empty(o), ]
  expect_gt(nrow(sf::st_coordinates(vis)), 1000L)
  # And it still draws.
  expect_s3_class(ggplot2::ggplot() + ggplot2::geom_sf(data = o), "ggplot")
})

# simplify_geometry() took a homogeneous MULTIPOLYGON column -- which
# get_world_sf() goes out of its way to guarantee -- and handed back a mixed
# sfc_GEOMETRY one, because both simplifiers collapse a single-part
# MULTIPOLYGON to a POLYGON. sf::st_coordinates() is not implemented for that,
# so the fix applied at the source was undone downstream.

test_that("simplify_geometry preserves a homogeneous geometry column", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  g <- world_geometry("countries", geometry = "sf")
  expect_equal(unique(as.character(sf::st_geometry_type(g))), "MULTIPOLYGON")
  for (rm_present in c(TRUE, FALSE)) {
    out <- if (rm_present) {
      skip_if_not_installed("rmapshaper")
      suppressWarnings(simplify_geometry(g, keep = 0.1))
    } else {
      with_mocked_bindings(
        has_pkg = function(pkg) {
          if (identical(pkg, "rmapshaper")) FALSE
          else isTRUE(requireNamespace(pkg, quietly = TRUE))
        },
        suppressWarnings(simplify_geometry(g, keep = 0.1)))
    }
    expect_equal(unique(as.character(sf::st_geometry_type(out))), "MULTIPOLYGON")
    expect_no_error(sf::st_coordinates(out))
    expect_equal(nrow(out), nrow(g))
    expect_false(any(sf::st_is_empty(out)))
  }
})

test_that("the st_simplify fallback is CRS-independent and honours keep", {
  skip_slow_on_cran()
  # It used to pass a fixed dTolerance of (1 - keep) * 10000, i.e. metres
  # whatever the CRS: 9 km on a projected frame, which barely simplified
  # anything, and 9000 *degrees* on a lon/lat one, where only
  # preserveTopology kept the result usable at all.
  skip_if_no_sf_geometry()
  old_s2 <- suppressMessages(sf::sf_use_s2(FALSE))   # NE rings are s2-invalid
  on.exit(suppressMessages(sf::sf_use_s2(old_s2)), add = TRUE)
  proj <- world_geometry("countries", geometry = "sf")
  ll <- sf::st_transform(proj, 4326L)
  npts <- function(g) nrow(sf::st_coordinates(g))
  fallback <- function(x, k) {
    with_mocked_bindings(
      has_pkg = function(pkg) {
        if (identical(pkg, "rmapshaper")) FALSE
        else isTRUE(requireNamespace(pkg, quietly = TRUE))
      },
      suppressWarnings(simplify_geometry(x, keep = k)))
  }
  keeps <- c(0.9, 0.5, 0.1)
  for (x in list(proj, ll)) {
    v <- vapply(keeps, function(k) npts(fallback(x, k)), numeric(1))
    expect_true(all(diff(v) <= 0))          # a smaller keep simplifies more
    expect_gt(length(unique(v)), 1L)        # and keep actually does something
    expect_lt(v[1], npts(x))               # something was always removed
  }
  # The two coordinate systems now behave alike: a fixed metre tolerance did
  # not. Compare the proportion kept, within a few percent.
  for (k in keeps) {
    pp <- npts(fallback(proj, k)) / npts(proj)
    pl <- npts(fallback(ll, k)) / npts(ll)
    expect_lt(abs(pp - pl), 0.05)
  }
})

test_that("every geometry-returning path keeps a usable geometry column", {
  skip_slow_on_cran()
  # The invariant broke twice: st_break_antimeridian() downgraded the source
  # column (fixed in get_world_sf), and then simplify_geometry() undid the fix
  # downstream. Check the whole surface rather than the two known sites.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  paths <- list(
    countries  = function() world_geometry("countries", geometry = "sf"),
    centroids  = function() world_geometry("centroids", geometry = "sf"),
    coastline  = function() world_geometry("coastline", geometry = "sf"),
    borders    = function() world_geometry("borders", geometry = "sf"),
    graticule  = function() world_geometry("graticule", geometry = "sf"),
    ocean      = function() world_geometry("ocean", geometry = "sf"),
    region     = function() world_geometry("countries", geometry = "sf",
                                           region = "Europe"),
    bbox       = function() world_geometry("countries", geometry = "sf",
                                           region = c(-10, 35, 30, 60)),
    recentred  = function() world_geometry("countries", geometry = "sf",
                                           recenter = 150),
    projected  = function() attach_geometry(snap, geometry = "sf",
                                            projection = "mollweide"),
    attached   = function() attach_geometry(snap, geometry = "sf"),
    attach_sub = function() attach_geometry(snap, geometry = "sf",
                                            region = "Africa")
  )
  for (nm in names(paths)) {
    o <- suppressWarnings(paths[[nm]]())
    expect_s3_class(o, "sf")
    # One geometry type per column: a mixed column is an sfc_GEOMETRY, which
    # sf::st_coordinates() cannot read.
    expect_length(unique(as.character(sf::st_geometry_type(o))), 1L)
    expect_no_error(sf::st_coordinates(o))
    expect_false(any(sf::st_is_empty(o)), info = nm)
  }
  # And the same after simplifying, on both simplifier paths.
  skip_if_not_installed("rmapshaper")
  s1 <- suppressWarnings(simplify_geometry(
    attach_geometry(snap, geometry = "sf"), keep = 0.2))
  expect_length(unique(as.character(sf::st_geometry_type(s1))), 1L)
  expect_no_error(sf::st_coordinates(s1))
})

test_that("resolve_region reads every branch off the same trimmed value", {
  skip_slow_on_cran()
  # Only the iso3c branch trimmed, so one trailing space produced three
  # different outcomes: "FRA " resolved, "Europe " fell through to name
  # matching and errored, and "EU " was silently taken as a three-letter code
  # -- nchar is 3 and it is already uppercase -- so it reached the
  # "unknown code at face value" branch and came back as the string "EU ".
  # world_geometry(region = "EU ") then came back empty and said nothing, as
  # did world_data(), attach_geometry(), join_world() and country_borders() --
  # every public caller of this helper. (world_map() has no `region` argument;
  # it takes geometry that is already subset.)
  rr <- countryatlas:::resolve_region
  NB <- intToUtf8(0xA0)
  pad <- function(z) list(z, paste0(z, " "), paste0(z, NB), paste0(" ", z))

  # The silent one: a padded group must resolve to the group, not to a code.
  eu <- rr("EU")
  expect_gt(length(eu), 20L)
  for (v in pad("EU")) expect_equal(rr(v), eu)
  for (v in pad("EU")) expect_false(identical(rr(v), v))

  # Every shipped group agrees across padding forms.
  for (grp in unique(country_groups_tbl$group)) {
    want <- rr(grp)
    for (v in pad(grp)) expect_equal(rr(v), want)
  }

  # Continents, codes and names likewise.
  for (v in pad("Europe")) expect_equal(rr(v), rr("Europe"))
  for (v in pad("FRA")) expect_equal(rr(v), "FRA")
  for (v in pad("France")) expect_equal(rr(v), "FRA")
  # An unknown uppercase code is still passed through, now consistently.
  for (v in pad("ZZZ")) expect_equal(rr(v), "ZZZ")

  # Unpadded behaviour is untouched.
  expect_null(rr(NULL))
  expect_s3_class(rr(c(-10, 35, 30, 60)), "wdj_bbox")
  expect_error(rr(NA_character_), "must not contain missing values")
  expect_error(rr("Nowhere"), "matched no countries")
  expect_equal(rr(countryatlas:::wdj_known_iso3c()),
               countryatlas:::wdj_known_iso3c())
  # The error still quotes what the caller actually passed, untrimmed.
  expect_error(rr("Nowhere "), "Nowhere ")
})

test_that("a padded region reaches the public callers intact", {
  skip_slow_on_cran()
  # resolve_region() is internal; the defect was only visible through the
  # functions that call it, so pin it there too. Without this, the fix is
  # asserted one level below where a user would ever meet it.
  skip_if_no_sf_geometry()
  NB <- intToUtf8(0xA0)
  eu <- nrow(world_geometry("countries", geometry = "sf", region = "EU"))
  expect_gt(eu, 20L)
  for (v in list("EU ", " EU", paste0("EU", NB))) {
    expect_equal(nrow(world_geometry("countries", geometry = "sf", region = v)),
                 eu)
  }
  # country_borders() takes the same argument through the same helper.
  b <- nrow(country_borders(region = "EU"))
  expect_gt(b, 0L)
  expect_equal(nrow(country_borders(region = "EU ")), b)
  # And a padded continent, which used to error rather than resolve.
  af <- nrow(world_geometry("countries", geometry = "sf", region = "Africa"))
  expect_gt(af, 40L)
  expect_equal(nrow(world_geometry("countries", geometry = "sf",
                                   region = "Africa ")), af)
})

test_that("recentring splits countries at the seam without losing any", {
  skip_slow_on_cran()
  # Recentring rotates the world so a chosen longitude is the middle, which
  # cuts whatever straddles the new seam. The row count therefore *grows* --
  # Russia and the USA become two pieces at recenter = 180 -- and that is
  # correct. What must never happen is a country disappearing, an empty
  # geometry appearing, or area going missing beyond the sliver the cut
  # removes. None of the 32 existing recenter assertions covered any of that,
  # so a regression in the seam handling could have dropped countries from
  # every recentred map silently.
  skip_if_no_sf_geometry()
  gws <- countryatlas:::get_world_sf
  base <- gws(projection = "equal_earth")
  iso0 <- sort(unique(stats::na.omit(base$iso3c)))
  area <- function(x) as.numeric(sum(sf::st_area(sf::st_make_valid(x))))
  a0 <- area(base)
  expect_gt(length(iso0), 150L)
  expect_equal(sum(sf::st_is_empty(base)), 0L)

  for (rc in list(0, 11, 150, 180, -180)) {
    r <- gws(projection = "equal_earth", recenter = rc)
    # Not one country may go missing.
    expect_true(all(iso0 %in% r$iso3c),
                info = paste("countries lost at recenter =", rc))
    # Splitting is allowed; shrinking is not.
    expect_gte(nrow(r), nrow(base))
    # No empty geometry may appear.
    expect_equal(sum(sf::st_is_empty(r)), 0L,
                 info = paste("empty geometry at recenter =", rc))
    # Area survives the cut: only the seam sliver goes.
    expect_equal(area(r) / a0, 1, tolerance = 0.01)
  }

  # recenter = NULL and recenter = 0 both mean "leave it alone", so they must
  # agree with each other and change nothing.
  expect_equal(nrow(gws(projection = "equal_earth", recenter = 0)), nrow(base))
  expect_equal(area(gws(projection = "equal_earth", recenter = 0)) / a0, 1,
               tolerance = 1e-6)

  # The countries that actually straddle 180 are the ones at risk, so name
  # them: they must still be there, and non-empty, after the cut.
  at_seam <- intersect(c("RUS", "USA", "NZL", "FJI"), iso0)
  expect_gt(length(at_seam), 1L)
  r180 <- gws(projection = "equal_earth", recenter = 180)
  for (k in at_seam) {
    piece <- r180[!is.na(r180$iso3c) & r180$iso3c == k, ]
    expect_gt(nrow(piece), 0L)
    expect_false(any(sf::st_is_empty(piece)))
  }
})

test_that("plate_carree is equirectangular and new projections build", {
  expect_match(countryatlas:::wdj_crs("plate_carree"), "proj=eqc")
  expect_false(grepl("proj=longlat", countryatlas:::wdj_crs("plate_carree")))
  expect_match(countryatlas:::wdj_crs("winkel_tripel"), "proj=wintri")
  expect_match(countryatlas:::wdj_crs("orthographic", lat0 = 30), "lat_0=30")
})

test_that("polygon centroids are one antimeridian-safe row per iso3c", {
  skip_slow_on_cran()
  cent <- world_geometry("centroids", geometry = "polygon")
  expect_equal(anyDuplicated(cent$iso3c), 0L)
  # USA centroid sits on the contiguous landmass, not pulled to ~0 by Alaska.
  usa_lon <- cent$centroid_lon[cent$iso3c == "USA"]
  expect_lt(usa_lon, -60)
})

test_that("distance_between computes symmetric great-circle distances", {
  d1 <- distance_between("France", "Germany")
  d2 <- distance_between("Germany", "France")
  expect_equal(d1, d2)
  expect_gt(d1, 0)
  expect_lt(d1, 2000)
  expect_warning(w <- distance_between("Wakanda", "France"),
                 "did not resolve to a country")
  expect_true(is.na(w))
  # France is closer to Germany than to Australia.
  expect_lt(distance_between("France", "Germany"),
            distance_between("France", "Australia"))
  # Recycles a length-1 argument against a longer one, the usual R way.
  expect_length(distance_between("USA", c("Canada", "Mexico", "France")), 3)
})

test_that("country_borders and neighbors need sf", {
  skip_if(requireNamespace("sf", quietly = TRUE))
  # Pinned to the package gate itself, not merely "it errored". With no
  # pattern this accepted any condition at all -- a typo in the fixture, or
  # an argument error raised before the gate was reached -- and this block
  # only runs when the package is *absent*, which is the one configuration
  # nobody watches. The already-pinned ggsql block below documents the same
  # hazard. need_pkg() -> rlang::check_installed() raises
  # "rlib_error_package_not_found".
  expect_error(country_borders(), class = "rlib_error_package_not_found")
  expect_error(country_borders(), "sf")
  # neighbors() resolves the code first and only then reaches country_borders(),
  # so this also pins that the gate is what stops it -- not name resolution.
  expect_error(neighbors("FRA", origin = "iso3c"), class = "rlib_error_package_not_found")
  expect_error(neighbors("FRA", origin = "iso3c"), "sf")
})

test_that("country_borders finds real neighbours (needs sf)", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  b <- country_borders()
  expect_true(all(c("iso3c_a", "country_a", "iso3c_b", "country_b") %in% names(b)))
  expect_false(any(b$iso3c_a == b$iso3c_b))
  key <- paste(pmin(b$iso3c_a, b$iso3c_b), pmax(b$iso3c_a, b$iso3c_b))
  expect_equal(anyDuplicated(key), 0L)
  fra_deu <- (b$iso3c_a == "FRA" & b$iso3c_b == "DEU") |
    (b$iso3c_a == "DEU" & b$iso3c_b == "FRA")
  expect_true(any(fra_deu))
})

test_that("neighbors looks up a country's borders (needs sf)", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  fra <- neighbors("France")
  expect_true(all(fra$iso3c == "FRA"))
  expect_true("DEU" %in% fra$neighbor)
  # Japan is an island nation with no land border.
  expect_equal(nrow(neighbors("Japan")), 0L)
})

# country_borders() keeps one direction of each pair and asserts in a comment
# that "a country never borders itself". neighbors() then rebuilds both
# directions. Those are invariants a geometry or Natural Earth change could
# quietly break, so pin them rather than trusting the comment.

test_that("the border adjacency is irreflexive and de-duplicated", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  b <- country_borders()
  expect_gt(nrow(b), 100L)
  expect_equal(sum(b$iso3c_a == b$iso3c_b), 0L)        # no country borders itself
  # One direction per pair, not both.
  key <- paste(pmin(b$iso3c_a, b$iso3c_b), pmax(b$iso3c_a, b$iso3c_b))
  expect_equal(sum(duplicated(key)), 0L)
  expect_false(anyNA(c(b$iso3c_a, b$iso3c_b)))
})

test_that("neighbors() builds the adjacency once, however many countries", {
  # ?neighbors tells the reader to pass a vector rather than loop, because every
  # call rebuilds the whole world's st_touches() adjacency. Pin the fact that
  # claim rests on -- one country_borders() call per neighbors() call, not one
  # per country -- rather than a wall-clock assertion, which would be flaky.
  # Measured cost of getting this wrong: 0.43s for one country, 0.37s for 153,
  # so looping over them would be ~66s, about 177x a single vectorised call.
  skip_if_no_sf_geometry()
  calls <- 0L
  fake <- function(scale = "small", region = NULL) {
    calls <<- calls + 1L
    tibble::tibble(iso3c_a = c("FRA", "FRA", "DEU"),
                   country_a = c("France", "France", "Germany"),
                   iso3c_b = c("DEU", "ESP", "POL"),
                   country_b = c("Germany", "Spain", "Poland"))
  }
  testthat::local_mocked_bindings(country_borders = fake)

  calls <- 0L
  one <- neighbors("FRA", origin = "iso3c")
  expect_identical(calls, 1L)

  calls <- 0L
  many <- neighbors(c("FRA", "DEU", "ESP", "POL"), origin = "iso3c")
  expect_identical(calls, 1L)

  # And the vectorised answer really is the union of the individual ones.
  expect_setequal(one$neighbor, c("DEU", "ESP"))
  expect_setequal(many$neighbor[many$iso3c == "FRA"], c("DEU", "ESP"))
  expect_gt(nrow(many), nrow(one))
})

test_that("neighbors() is symmetric even though country_borders() is not", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  # neighbors() returns a tibble (iso3c, neighbor, neighbor_country) -- pin the
  # shape too, since the symmetry check depends on reading the right column.
  nb <- neighbors("France")
  expect_s3_class(nb, "tbl_df")
  expect_named(nb, c("iso3c", "neighbor", "neighbor_country"))

  b <- country_borders()
  codes <- sort(unique(c(b$iso3c_a, b$iso3c_b)))
  # One vectorised call, not one per country. neighbors() recomputes the whole
  # world's st_touches() adjacency on every call, and asking per country -- then
  # again per neighbour, to check the reverse edge -- meant ~465 rebuilds and 292
  # seconds, four fifths of the entire test suite. The function is vectorised, so
  # a single call does exactly the same work and exercises the same code.
  all_nb <- neighbors(codes, origin = "iso3c")
  expect_setequal(unique(all_nb$iso3c), codes)

  # No self-border, no repeated pair -- reported as the offending rows, so a
  # failure still names the country rather than just a count.
  expect_equal(all_nb$iso3c[all_nb$iso3c == all_nb$neighbor], character(0))
  dup <- all_nb[duplicated(all_nb[, c("iso3c", "neighbor")]), ]
  expect_equal(nrow(dup), 0L)

  # Symmetry: every (a, b) edge has its (b, a) twin.
  fwd <- paste(all_nb$iso3c, all_nb$neighbor)
  rev <- paste(all_nb$neighbor, all_nb$iso3c)
  expect_equal(setdiff(fwd, rev), character(0))

  nbr <- function(a) all_nb$neighbor[all_nb$iso3c == a]
  # A land border across an overseas territory is real, not a bug: French
  # Guiana borders Brazil and Suriname.
  expect_true(all(c("BRA", "SUR") %in% nbr("FRA")))
  # Vectorised input returns the union, keyed by the country asked for, and
  # agrees with the same lookup by name.
  v <- neighbors(c("France", "Germany"), origin = "country.name")
  expect_equal(nrow(v), length(nbr("FRA")) + length(nbr("DEU")))
  expect_setequal(unique(v$iso3c), c("FRA", "DEU"))
  expect_setequal(v$neighbor[v$iso3c == "FRA"], nbr("FRA"))
})

# --- Bug: locate_country(points=) leaked a raw sf error -----------------------

test_that("locate_country names a bad points argument", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  expect_error(locate_country(points = data.frame(lon = 1, lat = 1)),
               "must be an .*sf.* POINT object")
  expect_error(locate_country(points = data.frame(lon = 1, lat = 1)), "st_as_sf")
  expect_error(locate_country(points = "nope"), "must be an .*sf.* POINT object")
  expect_error(locate_country(points = 42), "lon")
})

# --- Bug: world_map(projection = "mercator") drew a sliver over a grey slab ---

test_that("mercator is clipped to a usable latitude band", {
  skip_slow_on_cran()
  d <- sf_df()
  expect_equal(countryatlas:::wdj_lat_limits("mercator"), c(-85.05113, 85.05113))
  expect_null(countryatlas:::wdj_lat_limits("equal_earth"))
  # Unclipped, Natural Earth's Antarctica reaches -90 where Mercator's y goes to
  # infinity: PROJ clamped rather than erroring and the panel came out three
  # times taller than the world is wide, the inhabited part a sliver at the top.
  b <- ggplot2::ggplot_build(world_map(d, gdp_per_capita, projection = "mercator"))
  pp <- b$layout$panel_params[[1]]
  aspect <- diff(pp$y_range) / diff(pp$x_range)
  expect_lt(aspect, 1.6)
})

test_that("the Earth radius is one constant, not three literals", {
  expect_equal(countryatlas:::EARTH_RADIUS_KM, 6371.0088)
  # Deparse the functions rather than reading R/geometry.R: the source tree is
  # not there under `R CMD check`, and the thing worth asserting is that these
  # three all reach for the shared constant, not that one file happens to
  # contain the number once.
  fns <- list(countryatlas:::ring_area_km2, countryatlas:::haversine_km,
              countryatlas::tissot_map)
  bodies <- vapply(fns, function(f) paste(deparse(f), collapse = " "), character(1))
  # The numeric literals in each body, not a text search: under covr every
  # expression is wrapped in a counter whose key carries line numbers of the
  # collated source, and one of them can contain "6371" by chance.
  numbers <- function(e) {
    if (is.numeric(e)) return(e)
    if (is.call(e) || is.pairlist(e) || is.expression(e)) {
      return(unlist(lapply(as.list(e), numbers)))
    }
    NULL
  }
  lits <- unlist(lapply(fns, function(f) numbers(body(f))))
  expect_false(any(abs(lits - 6371) < 1))
  expect_true(all(grepl("EARTH_RADIUS_KM", bodies, fixed = TRUE)))
})

test_that("world_geometry and attach_geometry route year to CShapes", {
  skip_slow_on_cran()
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  expect_s3_class(world_geometry("countries", year = 1970), "sf")
  expect_error(world_geometry("coastline", year = 1970), "only available for")
  expect_error(world_geometry("countries", year = 1970, region = "Africa"),
               "cannot be combined")
  h <- suppressWarnings(attach_geometry(snap[, c("iso3c", "gdp_per_capita")],
                                        year = 1970))
  expect_s3_class(h, "sf")
  expect_true(sum(!is.na(h$gdp_per_capita)) > 50)
})

# --- choice arguments name themselves when rejected ---------------------------------

test_that("a bad projection or scale is reported by name, from any entry point", {
  skip_slow_on_cran()
  # match.arg() on a variable inside a helper produces R's anonymous
  # "'arg' should be one of ..." -- naming neither the argument nor the function
  # the user actually called. Seventeen exported functions take `projection` and
  # nine take `scale`, so this was one bad message reachable a great many ways.
  skip_if_no_sf_geometry()
  d <- sf_df()
  named <- function(expr) {
    e <- tryCatch(expr, error = function(e) e)
    expect_s3_class(e, "countryatlas_error")
    conditionMessage(e)
  }
  expect_match(named(world_map(d, gdp_per_capita, projection = "nope")),
               "`projection` must be one of")
  expect_match(named(tissot_map("nope")), "`projection` must be one of")
  expect_match(named(projection_distortion("nope")), "`projection` must be one of")
  expect_match(named(world_geometry("countries", "sf", scale = "nope")),
               "`scale` must be one of")
  expect_match(named(country_borders(scale = "nope")), "`scale` must be one of")
  expect_match(named(neighbors("France", scale = "nope")), "`scale` must be one of")
  # `scale` is deprecated in morans_i() and still validated; the deprecation
  # note is not what this test is about.
  rlang::local_options(lifecycle_verbosity = "quiet")
  expect_match(named(morans_i(snap, gdp_per_capita, scale = "nope", n_perm = 0)),
               "`scale` must be one of")
  skip_if_not_installed("cartogram")
  expect_match(named(dorling_map(d, population, projection = "nope")),
               "`projection` must be one of")
})

test_that("attach_geometry says when the key matches nothing at all", {
  skip_slow_on_cran()
  # An unmatched code is ordinary here -- the basemap holds fewer countries than
  # the snapshot, since small states have no polygon at 110m -- so warning about
  # one would be noise. Zero matches is different: lowercase, mixed-case and
  # padded iso3c all matched nothing, and every country then drew as no-data
  # with nothing said. standardize_country() normalises all three.
  bad <- function(v) tibble::tibble(iso3c = v, v = seq_along(v))
  for (v in list(c("fra", "deu"), c("Fra", "Deu"), c(" FRA ", " DEU "))) {
    expect_warning(attach_geometry(bad(v), geometry = "polygon"),
                   "matches the geometry")
  }
  # Correct codes, and the full snapshot, stay quiet.
  expect_no_warning(attach_geometry(bad(c("FRA", "DEU")), geometry = "polygon"))
  expect_no_warning(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  # And the same for the sf backend.
  skip_if_no_sf_geometry()
  expect_warning(attach_geometry(bad(c("fra", "deu")), geometry = "sf"),
                 "matches the geometry")
  expect_no_warning(
    attach_geometry(world_snapshot$countries, geometry = "sf"))
})

test_that("simplify_geometry and theme_world_map validate their first argument", {
  skip_slow_on_cran()
  # Both checked their *second* argument carefully and their first not at all.
  # simplify_geometry() reached rmapshaper and leaked "no applicable method for
  # 'ms_simplify' applied to an object of class NULL" -- naming rmapshaper's
  # generic, not the argument -- and failed differently again through the
  # st_simplify() fallback, so the message depended on which optional package
  # the caller had. theme_world_map() got base R's bare "non-numeric argument
  # to binary operator".
  skip_if_not_installed("sf")
  for (bad in list(NULL, list(), NA, data.frame())) {
    expect_error(simplify_geometry(bad), "must be an <sf> frame")
  }
  expect_error(theme_world_map(list()), "base_size")
  expect_error(theme_world_map("a"), "base_size")
  expect_error(theme_world_map(NULL), "base_size")
  expect_error(theme_world_map(base_family = 1), "base_family")

  # Both still work on valid input, sf frame and bare sfc alike.
  skip_if_not_installed("rnaturalearth")
  g <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "sf"))
  expect_s3_class(suppressWarnings(simplify_geometry(g, keep = 0.1)), "sf")
  expect_s3_class(suppressWarnings(
    simplify_geometry(sf::st_geometry(g), keep = 0.1)), "sfc")
  expect_s3_class(theme_world_map(), "theme")
  expect_s3_class(theme_world_map(14), "theme")
})

test_that("distance_between separates a missing centroid from a bad name", {
  skip_slow_on_cran()
  # Two reasons for an NA distance, and only one is the documented gap.
  # "Resolved to a country that has no bundled centroid" is expected --
  # ?distance_between says so and country_weights() already reports it -- so it
  # must stay quiet. "Did not resolve to a country at all", usually the wrong
  # `origin`, returned a column of NA with nothing said.
  meta <- countryatlas::country_meta
  no_centroid <- setdiff(meta$iso3c,
                         meta$iso3c[!is.na(meta$centroid_lon)])

  # The documented gaps stay quiet.
  if (length(no_centroid)) {
    expect_no_warning(
      distance_between(utils::head(no_centroid, 3), "FRA", origin = "iso3c"))
  }
  expect_no_warning(distance_between("Kosovo", "Serbia"))
  expect_no_warning(distance_between("France", "Germany"))

  # A name that is not a country does not.
  expect_warning(distance_between("France", "Freedonia"),
                 "did not resolve to a country")
  # Nor does the classic mistake of reading names with origin = "iso3c".
  expect_warning(d <- distance_between("France", "Germany", origin = "iso3c"),
                 "Check `origin`")
  expect_true(is.na(d))
  # The distances themselves are unchanged.
  expect_equal(round(distance_between("France", "Germany")), 802)
})

test_that("region reports a no-match instead of drawing an empty map", {
  skip_slow_on_cran()
  # `region` accepts a continent, a group, iso3c codes, country names or a
  # bounding box -- and anything that matched none of those fell through to
  # name-matching, resolved to NA, and produced a silent empty subset. A typo
  # like "Europ" gave a blank map with no explanation, and NA reached the
  # nchar()/%in% tests as base R's "missing value where TRUE/FALSE needed".
  wg <- function(r) world_geometry("countries", geometry = "polygon", region = r)

  expect_error(wg("Nowhere"), "matched no countries")
  expect_error(wg("Europ"), "matched no countries")
  # A number is only ever a bounding box, and says so rather than being read
  # as a country name.
  expect_error(wg(1), "bounding box of four numbers")
  expect_error(wg(NA), "must not contain missing values")
  expect_error(wg(c("France", NA)), "must not contain missing values")

  # All five documented forms still work.
  expect_gt(nrow(wg("Europe")), 0L)              # continent
  expect_gt(nrow(wg("EU")), 0L)                  # group
  expect_gt(nrow(wg(c("FRA", "DEU"))), 0L)       # iso3c
  expect_gt(nrow(wg(c("France", "Germany"))), 0L) # names
  # A bounding box warns that it clips vertices, which is its own test.
  expect_gt(nrow(suppressWarnings(wg(c(-10, 30, 40, 48)))), 0L) # bounding box
  expect_gt(nrow(world_geometry("countries", geometry = "polygon")), 0L) # NULL
  # Codes and names for the same countries agree.
  expect_equal(nrow(wg(c("FRA", "DEU"))), nrow(wg(c("France", "Germany"))))
})

test_that("the pinned microstate lists match what the finer basemap shows", {
  # WDJ_MICROSTATES and WDJ_MICROSTATE_NEIGHBOURS are hard-coded, so pin them
  # against scale = "medium", which does carry the five. A Natural Earth update
  # that changes either must fail here rather than leave the factsheet note
  # quietly wrong.
  skip_if_no_sf_geometry()
  skip_on_cran()
  med <- country_borders(scale = "medium")
  small <- country_borders(scale = "small")
  micro <- countryatlas:::WDJ_MICROSTATES
  # Present at 50m, absent at 110m -- the premise of the whole note.
  expect_true(all(micro %in% c(med$iso3c_a, med$iso3c_b)))
  expect_false(any(micro %in% c(small$iso3c_a, small$iso3c_b)))
  # And the neighbour map is exactly who borders them at 50m.
  pairs <- rbind(
    data.frame(a = med$iso3c_a, b = med$iso3c_b),
    data.frame(a = med$iso3c_b, b = med$iso3c_a))
  observed <- lapply(split(pairs$b, pairs$a), function(x) sort(intersect(x, micro)))
  observed <- observed[vapply(observed, length, 0L) > 0 &
                         !names(observed) %in% micro]
  expected <- lapply(countryatlas:::WDJ_MICROSTATE_NEIGHBOURS, sort)
  expect_equal(observed[order(names(observed))], expected[order(names(expected))])
})

test_that("a wrong `origin` is our error, naming the scheme you meant", {
  skip_slow_on_cran()
  # `origin` is user-facing on a dozen exported functions -- neighbors(),
  # country_join(), standardize_country(), in_group() -- and check_string()
  # only proved it was a string. An invalid scheme therefore travelled into
  # countrycode::countrycode() and died there, blaming an `origin` argument
  # the caller never passed and listing forty schemes.
  expect_error(neighbors("France", origin = "country"),
               class = "countryatlas_bad_origin")
  expect_error(country_timeline("FRA", origin = "ISO3C"),
               class = "countryatlas_bad_origin")
  expect_error(in_group("France", "EU", origin = "name"),
               class = "countryatlas_bad_origin")

  # The scheme someone half-remembers is a *fragment* of the real name, which
  # edit distance ranks badly: "country" is five edits from "country.name", so
  # the one suggestion that mattered was missing, while "name" was answered
  # with "fao" and "imf" at distance three.
  hint <- function(o) {
    msg <- cli::ansi_strip(tryCatch(wdj_to_iso3c("France", origin = o),
                                    error = conditionMessage))
    gsub("[[:space:]]+", " ", msg)
  }
  expect_match(hint("country"), "Did you mean [^?]*country[.]name")
  expect_match(hint("name"), "Did you mean [^?]*country[.]name")
  expect_match(hint("country_name"), "Did you mean [^?]*country[.]name")
  expect_match(hint("iso3"), "Did you mean [^?]*iso3c")
  expect_match(hint("ISO3C"), "Did you mean [^?]*iso3c")
  # Nonsense gets no invented suggestion.
  expect_false(grepl("Did you mean", hint("zzz")))

  # Valid schemes are untouched, including the iso3c fast path.
  expect_identical(wdj_to_iso3c("France"), "FRA")
  expect_identical(wdj_to_iso3c("fra", origin = "iso3c"), "FRA")
  expect_identical(wdj_to_iso3c("FR", origin = "iso2c"), "FRA")
  expect_identical(wdj_to_iso3c("FRA", origin = "wb"), "FRA")
})

test_that("neighbors tells a typo from a country with no land border", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  # Both return zero rows. Only one of them is a mistake, and the function used
  # to be silent about either -- while distance_between() and convert_country()
  # both report an unresolved value.
  expect_no_warning(fr <- neighbors("France"))
  expect_gt(nrow(fr), 0L)
  expect_no_warning(ice <- neighbors("Iceland"))
  expect_equal(nrow(ice), 0L)            # a real zero stays quiet

  w <- tryCatch(neighbors("Nowhereland"), warning = function(x) x)
  msg <- gsub("[[:space:]]+", " ",
              cli::ansi_strip(paste(conditionMessage(w), collapse = " ")))
  expect_match(msg, "1 value did not resolve", fixed = TRUE)
  expect_match(msg, "it has no neighbours", fixed = TRUE)
  expect_match(msg, "Nowhereland", fixed = TRUE)
  # Agrees at n = 2, verb included.
  expect_match(gsub("[[:space:]]+", " ", cli::ansi_strip(paste(conditionMessage(
    tryCatch(neighbors(c("Nowhereland", "Atlantis")), warning = function(x) x)),
    collapse = " "))), "2 values did not resolve", fixed = TRUE)

  # A resolved name still returns its borders even alongside an unresolved one.
  got <- suppressWarnings(neighbors(c("France", "Nowhereland")))
  expect_equal(nrow(got), nrow(fr))
  expect_no_warning(neighbors("Nowhereland", warn = FALSE))
  expect_error(neighbors("France", warn = "x"), "`warn`")
})

test_that("the polygon backend says when it is ignoring projection", {
  skip_slow_on_cran()
  # `recenter` already warned when it could not be honoured; `projection` was
  # documented for the sf backend but taken and dropped in silence.
  expect_warning(world_geometry(projection = "mollweide"),
                 class = "countryatlas_projection_ignored")
  d <- data.frame(iso3c = c("FRA", "DEU"), gdp = 1:2)
  expect_warning(attach_geometry(d, projection = "mollweide"),
                 class = "countryatlas_projection_ignored")
  # The default, and an explicit restatement of it, stay quiet.
  expect_no_warning(world_geometry())
  expect_no_warning(world_geometry(projection = "equal_earth"))
  # The sf backend honours both, so neither warns there.
  skip_if_no_sf_geometry()
  expect_no_warning(world_geometry(geometry = "sf", projection = "mollweide"))
  expect_no_warning(world_geometry(geometry = "sf", recenter = 150))
})

test_that("a multi-value scale is rejected before it becomes a cache key", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  # paste0("scale_", scale) vectorised, so `[[` on the cache environment failed
  # with base R's "wrong arguments for subsetting an environment". The scalar
  # bad values all reached the real check and reported properly.
  expect_error(country_borders(scale = c("small", "large")),
               "must be one of", class = "countryatlas_error")
  expect_error(world_geometry(geometry = "sf", scale = c("small", "large")),
               "must be one of", class = "countryatlas_error")
  for (bad in list("smal", 2, NA_character_, NULL)) {
    expect_error(country_borders(scale = bad), class = "countryatlas_error")
  }
  # Passing the full choice vector still means "take the default", as
  # match.arg() would.
  expect_s3_class(world_geometry(geometry = "sf",
                                 scale = c("small", "medium", "large")), "sf")
})

test_that("the polygon backend says when it is ignoring scale", {
  # It serves one bundled resolution, so `scale` cannot be honoured -- but it
  # was accepted in silence, and `scale = 2` was not even rejected.
  expect_warning(world_geometry(scale = "large"),
                 class = "countryatlas_scale_ignored")
  expect_warning(world_geometry(scale = 2),
                 class = "countryatlas_scale_ignored")
  d <- data.frame(iso3c = c("FRA", "DEU"), gdp = 1:2)
  expect_warning(attach_geometry(d, scale = "large"),
                 class = "countryatlas_scale_ignored")
  # The default is what the backend actually serves, so it stays quiet.
  expect_no_warning(world_geometry())
  expect_no_warning(attach_geometry(d))
  expect_no_warning(world_geometry(scale = "small"))
})

test_that("a data frame is refused where a country vector belongs", {
  skip_slow_on_cran()
  # as.character() on a data frame deparses each *column* into a string, so
  # neighbors(my_df) came back with the two "countries" `c("USA", "FRA")` and
  # `c(1, 2)` -- silently, because those are just strings that match nothing
  # and every row then reads as "country not found". Nearly every other verb
  # here takes `data` first, so handing a frame to the ones that take a vector
  # is the natural mistake. gini() and theil() already refused it; these eight
  # did not.
  d <- data.frame(iso3c = c("USA", "FRA"), v = c(1, 2))
  expect_error(neighbors(d), class = "countryatlas_frame_as_vector")
  expect_error(convert_country(d), class = "countryatlas_frame_as_vector")
  expect_error(country_timeline(d), class = "countryatlas_frame_as_vector")
  expect_error(dissolve_country(d), class = "countryatlas_frame_as_vector")
  expect_error(in_group(d, "EU"), class = "countryatlas_frame_as_vector")
  expect_error(distance_between(d, d), class = "countryatlas_frame_as_vector")
  expect_error(check_country_match(d), class = "countryatlas_frame_as_vector")
  expect_error(repair_country_names(d), class = "countryatlas_frame_as_vector")

  # Four of them run as.character() before reaching wdj_to_iso3c(), so the
  # guard has to sit at each coercion point, not only at the shared one.
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    check_country_match(d), error = identity))), "not a data frame",
    fixed = TRUE)

  # A data frame is only the common case: as.character() deparses any list
  # element that is not a single value, so list(c("FRA", "DEU")) collapsed to
  # the one string `c("FRA", "DEU")` and convert_country() returned a single NA
  # where two codes were asked for.
  expect_error(convert_country(list(c("FRA", "DEU")), origin = "iso3c"),
               class = "countryatlas_frame_as_vector")
  expect_error(neighbors(list(c("FRA", "DEU")), origin = "iso3c"),
               class = "countryatlas_frame_as_vector")
  expect_error(dissolve_country(list(c("USSR", "Yugoslavia"))),
               class = "countryatlas_frame_as_vector")
  expect_error(convert_country(list(NULL), origin = "iso3c"),
               class = "countryatlas_frame_as_vector")

  # Shapes that as.character() coerces correctly are left alone: a flat list of
  # scalars, a matrix, and an empty list.
  expect_identical(convert_country(list("FRA", "DEU"), origin = "iso3c"),
                   c("FRA", "DEU"))
  expect_identical(convert_country(matrix(c("FRA", "DEU")), origin = "iso3c"),
                   c("FRA", "DEU"))
  expect_length(convert_country(list(), origin = "iso3c"), 0L)

  # Vectors of every shape still work, including factors and empty ones.
  expect_s3_class(dissolve_country(c("USSR", "Yugoslavia")), "data.frame")
  expect_s3_class(dissolve_country(character(0)), "data.frame")
  expect_s3_class(check_country_match(c("France", "Narnia")), "data.frame")
  expect_type(repair_country_names(c("Frnace", "Japan")), "character")
  expect_type(repair_country_names(factor("Frnace")), "character")
  expect_type(convert_country(factor("France")), "character")
  expect_true(suppressWarnings(in_group("FRA", "EU", origin = "iso3c")))
})

test_that("region accepts ISO codes in any case", {
  # Lowercase used to half-resolve: countrycode's case-insensitive name regex
  # matched "usa" but not "can", so region = c("usa", "can") silently dropped
  # Canada instead of subsetting to both.
  rr <- countryatlas:::resolve_region
  expect_equal(rr(c("usa", "can")), c("USA", "CAN"))
  expect_equal(rr(c("Usa", "cAn")), c("USA", "CAN"))
  expect_equal(rr(c("USA", "CAN")), c("USA", "CAN"))
  expect_equal(rr(c(" usa ", "can")), c("USA", "CAN"))
  # An all-uppercase unknown code is still taken at face value (an empty
  # subset), not reinterpreted as a country name.
  expect_equal(rr("XYZ"), "XYZ")
  # Names, continents, groups and bounding boxes are untouched.
  expect_equal(rr(c("United States", "Canada")), c("USA", "CAN"))
  expect_gt(length(rr("Africa")), 40L)
  expect_equal(length(rr("EU")), 27L)
  expect_s3_class(rr(c(-20, 30, 40, 70)), "wdj_bbox")
  expect_null(rr(NULL))
})

test_that("region subsetting gives the same geometry for either case", {
  lower <- world_geometry("countries", geometry = "polygon",
                          region = c("usa", "can"))
  upper <- world_geometry("countries", geometry = "polygon",
                          region = c("USA", "CAN"))
  expect_equal(nrow(lower), nrow(upper))
  expect_gt(nrow(lower), 0L)
  expect_setequal(unique(lower$iso3c), c("USA", "CAN"))
})

test_that("the sf happy path prints nothing to the console", {
  skip_slow_on_cran()
  # st_break_antimeridian() runs on every sf call and emits three notices
  # ("Spherical geometry (s2) switched off/on", plus st_intersection's planar
  # note). Unsilenced, a plain attach_geometry(geometry = "sf") printed them.
  skip_if_no_sf_geometry()
  skip_if(sink.number(type = "message") != 2L,
          "a message sink is already active")
  snap <- countryatlas::world_snapshot$countries

  stderr_lines <- function(expr) {
    f <- tempfile()
    con <- file(f, "w")
    sink(con, type = "message")
    on.exit({
      if (sink.number(type = "message") != 2L) sink(type = "message")
      close(con)
    }, add = TRUE)
    try(force(expr), silent = TRUE)
    if (sink.number(type = "message") != 2L) sink(type = "message")
    length(readLines(f, warn = FALSE))
  }

  expect_equal(stderr_lines(attach_geometry(snap, geometry = "sf")), 0L)
  expect_equal(stderr_lines(world_geometry("countries", geometry = "sf")), 0L)
  expect_equal(stderr_lines(country_borders(region = "Europe")), 0L)
  expect_equal(stderr_lines(locate_country(lon = 2.35, lat = 48.85)), 0L)
})

test_that("the sf happy path leaks no message conditions to the caller", {
  skip_slow_on_cran()
  # A clean console is not enough: redirecting the message *stream* leaves the
  # underlying message() conditions travelling to whatever handler the caller
  # has installed, so purrr::quietly(), capture_messages() or a plain
  # withCallingHandlers() around any sf-backed verb still saw sf's internal
  # chatter. Count conditions, not console lines -- they are separate channels.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries

  n_conditions <- function(expr) {
    n <- 0L
    withCallingHandlers(
      try(force(expr), silent = TRUE),
      message = function(m) {
        n <<- n + 1L
        invokeRestart("muffleMessage")
      }
    )
    n
  }

  expect_identical(n_conditions(attach_geometry(snap, geometry = "sf")), 0L)
  expect_identical(n_conditions(country_borders(region = "Europe")), 0L)
  expect_identical(n_conditions(locate_country(lon = 2.35, lat = 48.85)), 0L)
  expect_identical(n_conditions(neighbors("France")), 0L)
})

test_that("country_borders' column order is what the graph recipe assumes", {
  skip_slow_on_cran()
  # ?country_borders tells users to hand igraph only the two code columns,
  # because graph_from_data_frame() treats the FIRST TWO columns as the edge
  # endpoints -- and here columns 1 and 2 both describe endpoint A, so passing
  # the whole tibble builds edges from each country's code to its own name.
  # igraph is not a dependency, so assert the structural fact the advice rests
  # on rather than running it.
  skip_if_no_sf_geometry()
  b <- country_borders(region = "Europe")
  expect_equal(names(b), c("iso3c_a", "country_a", "iso3c_b", "country_b"))
  # Columns 1 and 2 are the same endpoint, not two endpoints.
  expect_equal(b$country_a,
               convert_country(b$iso3c_a, to = "country", origin = "iso3c",
                               warn = FALSE))
  expect_equal(b$country_b,
               convert_country(b$iso3c_b, to = "country", origin = "iso3c",
                               warn = FALSE))
  # The subset the docs recommend is a well-formed edge list.
  edges <- b[, c("iso3c_a", "iso3c_b")]
  expect_equal(ncol(edges), 2L)
  expect_true(all(nchar(unlist(edges)) == 3L))
  expect_false(any(edges$iso3c_a == edges$iso3c_b))
})

test_that('scale = "large" names the non-CRAN package it needs', {
  skip_slow_on_cran()
  # The 10m Natural Earth data lives in rnaturalearthhires, which is not on
  # CRAN and not in Suggests. Ungated, rnaturalearth reacts by trying to
  # install it into the user's library and then failing obscurely.
  skip_if_no_sf_geometry()
  skip_if(requireNamespace("rnaturalearthhires", quietly = TRUE),
          "rnaturalearthhires is installed, so the gate does not fire")
  expect_error(world_geometry("countries", geometry = "sf", scale = "large"),
               class = "countryatlas_error")
  expect_error(world_geometry("countries", geometry = "sf", scale = "large"),
               "rnaturalearthhires")
  # The two CRAN-available scales are unaffected.
  expect_s3_class(world_geometry("countries", geometry = "sf", scale = "small"), "sf")
  expect_s3_class(world_geometry("countries", geometry = "sf", scale = "medium"), "sf")
})

# dplyr joins default to na_matches = "na", i.e. an NA key matches another NA
# key. Natural Earth carries Somaliland as a polygon with no ISO code, so any
# unmatched country in the caller's data joined onto it: the value was painted
# on a real country, and with two or more unmatched rows the join fanned out
# many-to-many. country_join()/country_join_all() already passed
# na_matches = "never"; every other country-keyed join now does too.

test_that("an NA country key never joins to geometry", {
  skip_if_no_sf_geometry()
  geom <- world_geometry("countries", geometry = "sf")
  # The premise of the bug: the sf source really does carry a keyless feature.
  skip_if(!anyNA(geom$iso3c), "sf source has no keyless feature to mis-join to")

  df <- data.frame(iso3c = c("USA", NA, NA), value = c(1, 99, 77))
  out <- attach_geometry(df, geometry = "sf")
  expect_false(any(out$value %in% c(99, 77)))       # not painted on a country
  expect_equal(nrow(out), nrow(geom))               # and no many-to-many fan-out
  # The keyless feature is still drawn, just with no data attached.
  expect_true(all(is.na(out$value[is.na(out$iso3c)])))
  expect_equal(out$value[!is.na(out$iso3c) & out$iso3c == "USA"][1], 1)
})

test_that("PROJ strings always use a dot decimal", {
  old <- options(OutDec = ",", scipen = -9)
  on.exit(options(old), add = TRUE)
  s <- countryatlas:::wdj_crs("orthographic", recenter = 48.9, lat0 = 12.5)
  expect_match(s, "+lat_0=12.5", fixed = TRUE)
  expect_match(s, "+lon_0=48.9", fixed = TRUE)
  expect_false(grepl(",", s, fixed = TRUE))
  expect_false(grepl("e+", s, fixed = TRUE))
})

test_that("EPSG codes and Natural Earth scales are integer literals", {
  # A double is what breaks: sf and rnaturalearth both paste the number into a
  # name, and only doubles are subject to scipen.
  expect_type(countryatlas:::ne_scale("small"), "integer")
  expect_identical(countryatlas:::ne_scale("small"), 110L)
  expect_identical(countryatlas:::ne_scale("medium"), 50L)
  expect_identical(countryatlas:::ne_scale("large"), 10L)
  # Walk the AST rather than grepping the deparsed source. The regex form also
  # matched "4326" inside *string* literals -- locate_country()'s guard tells the
  # user to call sf::st_as_sf(..., crs = 4326), which is the right advice and
  # never becomes a number -- while an AST walk tests the thing that actually
  # matters: every numeric 4326 constant in the code is an integer.
  epsg_doubles <- function(f) {
    bad <- 0L
    walk <- function(e) {
      if (is.numeric(e) && length(e) == 1L && !is.na(e) && e == 4326 &&
          !is.integer(e)) {
        bad <<- bad + 1L
      }
      if (is.call(e) || is.expression(e)) {
        for (part in as.list(e)) {
          if (!missing(part) && !is.null(part)) try(walk(part), silent = TRUE)
        }
      }
      invisible(NULL)
    }
    walk(body(f))
    bad
  }
  fns <- list(countryatlas:::get_world_sf, countryatlas::locate_country,
              countryatlas::interactive_map, countryatlas::projection_compare,
              countryatlas::tissot_map)
  expect_equal(sum(vapply(fns, epsg_doubles, integer(1))), 0L)
})

test_that("a numeric region must be a well-formed bounding box", {
  skip_slow_on_cran()
  rr <- countryatlas:::resolve_region
  # These were taken as unknown three-letter codes and drew an empty map.
  expect_error(rr(250), "four numbers", class = "countryatlas_error")
  expect_error(rr(c(100, 200, 300)), "four numbers",
               class = "countryatlas_error")
  expect_error(rr(c(10, 60, -10, 30)), "xmin < xmax",
               class = "countryatlas_error")
  expect_error(rr(c(-Inf, 30, 10, 60)), class = "countryatlas_error")
  expect_s3_class(rr(c(-10, 35, 30, 70)), "wdj_bbox")
})

test_that("locate_country() answers zero points with zero rows, silently", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  expect_silent(out <- locate_country(numeric(0), numeric(0)))
  expect_equal(nrow(out), 0L)
  expect_named(out, c("iso3c", "country"))
})

# --- attach_geometry() ---------------------------------------------------------

test_that("attach_geometry() refuses a column the polygon backend draws with", {
  skip_slow_on_cran()
  for (col in c("group", "lat", "long", "order")) {
    d <- data.frame(iso3c = c("FRA", "DEU"), value = 1:2)
    d[[col]] <- c(1, 2)
    expect_error(attach_geometry(d, geometry = "polygon"),
                 class = "countryatlas_geometry_column_clash")
    expect_error(attach_geometry(d, geometry = "polygon"), col, fixed = TRUE)
  }
  # The sf backend keeps its geometry in one column, so the same frame is fine.
  skip_if_no_sf_geometry()
  d <- data.frame(iso3c = c("FRA", "DEU"), value = 1:2, group = c("a", "b"))
  out <- suppressWarnings(attach_geometry(d, geometry = "sf"))
  expect_s3_class(out, "sf")
  expect_equal(out$group[out$iso3c %in% "FRA"], "a")
})

test_that("a region vector with a name that matches nothing says so", {
  skip_slow_on_cran()
  expect_warning(iso <- countryatlas:::resolve_region(c("France", "Germny")),
                 class = "countryatlas_region_unmatched")
  expect_equal(stats::na.omit(iso)[[1]], "FRA")
  expect_warning(countryatlas:::resolve_region(c("France", "Germny")), "Germny")
  # Continent names are taken only on their own, and the refusal says that.
  expect_error(countryatlas:::resolve_region(c("Europe", "Asia")),
               "only on its own")
  # One resolvable name, or a code vector, stays silent.
  expect_silent(countryatlas:::resolve_region(c("France", "Germany")))
  expect_silent(countryatlas:::resolve_region(c("FRA", "DEU")))
})

test_that("polygon_parts() keeps one feature per input and only polygons", {
  skip_if_not_installed("sf")
  sq <- sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0))))
  ln <- sf::st_linestring(rbind(c(2, 2), c(3, 3)))
  g <- sf::st_sfc(sf::st_geometrycollection(list(ln, sq)), sq,
                  sf::st_geometrycollection(list(ln)), sf::st_multipolygon())
  out <- countryatlas:::polygon_parts(g)
  expect_length(out, 4L)
  expect_true(all(sf::st_geometry_type(out) == "MULTIPOLYGON"))
  expect_equal(sf::st_is_empty(out), c(FALSE, FALSE, TRUE, TRUE))
})

test_that("recenter = 360 works on the sf backend and 500 is refused by name", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  # Both reached sf::st_break_antimeridian() unvalidated and failed with
  # "polygons require at least 4 points".
  g360 <- suppressWarnings(world_geometry(geometry = "sf", recenter = 360))
  g0 <- suppressWarnings(world_geometry(geometry = "sf"))
  expect_equal(nrow(g360), nrow(g0))
  expect_error(world_geometry(geometry = "sf", recenter = 500),
               "must be between -360 and 360", class = "countryatlas_error")
  expect_error(attach_geometry(countryatlas::world_snapshot$countries,
                               geometry = "sf", recenter = -400),
               "must be between -360 and 360", class = "countryatlas_error")
})

test_that("a bounding-box region warns on the polygon backend", {
  # The polygon backend drops vertices instead of clipping, so a country across
  # the edge keeps a truncated ring that geom_polygon() closes with a chord --
  # France loses 202 of 605 vertices and the ends sit 15 degrees apart. The
  # returned tibble gives no sign of it, so the call has to say so.
  med <- c(-10, 30, 40, 48)
  expect_warning(pb <- world_geometry("countries", geometry = "polygon",
                                      region = med), "filters vertices")
  expect_true(all(pb$long >= med[1] & pb$long <= med[3]))
  expect_true(all(pb$lat >= med[2] & pb$lat <= med[4]))
  # Only for a box: naming countries or a continent selects whole shapes.
  expect_silent(world_geometry("countries", geometry = "polygon",
                               region = "Europe"))
  expect_silent(world_geometry("countries", geometry = "polygon"))
  skip_if_no_sf_geometry()
  # The sf backend does a real clip, and says nothing.
  expect_silent(world_geometry("countries", geometry = "sf", region = med))
})

test_that("label placement survives the antimeridian without `group`", {
  skip_slow_on_cran()
  # polygon_centroids() is exact because `group` identifies each country's
  # pieces and the label goes on the largest. Without it, a plain mean(range())
  # put every country that crosses 180 degrees on the far side of the planet:
  # measured against the largest-piece centroid, Fiji was 177.8 degrees out,
  # New Zealand 169.6, and the USA 96.6 (its Aleutian tail dragging the
  # mid-range into the Gulf of Guinea).
  poly <- attach_geometry(countryatlas::world_snapshot$countries,
                          geometry = "polygon")
  truth <- countryatlas:::polygon_centroids(poly)
  lon_of <- function(cc) {
    x <- poly$long[!is.na(poly$iso3c) & poly$iso3c == cc]
    c(plain = mean(range(x, na.rm = TRUE)),
      fixed = countryatlas:::antimeridian_centre(x),
      truth = truth$centroid_lon[truth$iso3c == cc])
  }
  # Russia too, on the Natural Earth basemap: its Chukotka tip is drawn east
  # of the antimeridian.
  for (cc in c("FJI", "NZL", "USA", "RUS")) {
    v <- lon_of(cc)
    expect_lt(abs(v[["fixed"]] - v[["truth"]]), abs(v[["plain"]] - v[["truth"]]))
  }
  expect_lt(abs(lon_of("FJI")[["fixed"]] - lon_of("FJI")[["truth"]]), 1)
  expect_lt(abs(lon_of("RUS")[["fixed"]] - lon_of("RUS")[["truth"]]), 2)
  # A country that never crosses the line is untouched.
  expect_equal(lon_of("BRA")[["fixed"]], lon_of("BRA")[["plain"]])
  # Antarctica encircles the pole rather than straddling the line, so longitude
  # is arbitrary and the wrap moves it: pinned so the trade-off stays visible.
  expect_equal(round(lon_of("ATA")[["fixed"]]), 180)

  # End to end: the group-less frame still labels every country.
  nogrp <- poly[, setdiff(names(poly), "group")]
  built <- ggplot2::ggplot_build(ggplot2::ggplot(nogrp) + geom_country_labels())
  expect_gt(nrow(built$data[[1]]), 200L)
  fj <- built$data[[1]]
  expect_gt(fj$x[fj$label == "FJI"], 170)
  # Uncoded pieces are not one "NA" country, on either path.
  expect_false(anyNA(fj$label))
})

test_that("the polygon backend is bundled Natural Earth and needs no maps", {
  # It drew maps::map_data("world") -- Natural Earth 1:50m as imported in
  # 2013 -- so a depends-only installation could not draw the default map, and
  # the two backends disagreed on which countries exist.
  ne <- with_mocked_bindings(
    countryatlas:::build_world_polygons(source = "ne"),
    need_pkg = function(pkg, ...) {
      if ("maps" %in% pkg) stop("the bundled polygons must not need maps")
    })
  expect_named(ne, c("long", "lat", "group", "order", "region", "subregion",
                     "iso3c", "iso2c"))
  expect_gt(nrow(ne), 90000L)
  expect_identical(ne$iso3c[ne$region == "France"][1], "FRA")
  expect_identical(ne$iso2c[ne$iso3c %in% "XKX"][1], "XK")
  # A custom override set re-keys by name, as on the sf backend.
  custom <- country_overrides(c(Somaliland = "SOM"))
  sm <- countryatlas:::build_world_polygons(custom, source = "ne")
  expect_true(all(sm$iso3c[sm$region == "Somaliland"] == "SOM"))
  expect_true(all(is.na(ne$iso3c[ne$region == "Somaliland"])))
})

test_that('geometry = "maps" is the deprecated way back', {
  skip_slow_on_cran()
  skip_if_not_installed("maps")
  # lifecycle warns once per session unless told otherwise.
  withr::local_options(lifecycle_verbosity = "warning")
  d <- data.frame(iso3c = c("FRA", "BRA"), v = 1:2)
  expect_warning(m <- attach_geometry(d, geometry = "maps"),
                 class = "lifecycle_warning_deprecated")
  expect_true(all(c("long", "lat", "group") %in% names(m)))
  # It is the maps package's own table, not the bundled one.
  expect_false(identical(nrow(m), nrow(attach_geometry(d))))
  expect_warning(world_geometry("countries", geometry = "maps"),
                 class = "lifecycle_warning_deprecated")
  expect_warning(join_world(data.frame(country = "France", v = 1),
                            geometry = "maps"),
                 class = "lifecycle_warning_deprecated")
  # Anything else is still refused by name.
  expect_error(attach_geometry(d, geometry = "map"), "geometry")
})

test_that("the polygon backend's scale message names its real resolution", {
  d <- data.frame(iso3c = "FRA", v = 1)
  # 1:50m is "medium", so asking for it is not ignored.
  expect_no_warning(attach_geometry(d, scale = "medium"))
  expect_warning(attach_geometry(d, scale = "large"),
                 "1:50m", class = "countryatlas_scale_ignored")
})
