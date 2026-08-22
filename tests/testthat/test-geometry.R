test_that("distance_between computes great-circle distance (no sf needed)", {
  d <- distance_between("France", "Germany")
  expect_type(d, "double")
  expect_gt(d, 0)
  # Paris–Berlin ~ 878 km, centroids should be in that ballpark
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
  d <- distance_between("France", "Atlantis")
  expect_true(is.na(d))
})

test_that("distance_between works on vectors of length 1 (no recycling)", {
  # Identical country -> zero distance
  d <- distance_between("France", "France")
  expect_true(abs(d) < 1e-9)
})

test_that("locate_country tags known capitals", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  out <- locate_country(lon = c(2.35, -74.0, 139.7), lat = c(48.85, 40.7, 35.7))
  # Paris, New York, Tokyo
  expect_equal(out$iso3c, c("FRA", "USA", "JPN"))
  expect_equal(out$country, c("France", "United States", "Japan"))
})

test_that("locate_country returns NA for open ocean", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  out <- locate_country(lon = -30, lat = -30)   # open Atlantic
  expect_true(is.na(out$iso3c))
})

test_that("locate_country supports extra attributes", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  out <- locate_country(lon = 2.35, lat = 48.85, add = c("country", "continent"))
  expect_equal(out$country, "France")
  expect_equal(out$continent, "Europe")
})

test_that("locate_country errors on mismatched lon/lat lengths", {
  skip_if_no_sf_geometry()
  expect_error(locate_country(lon = 1:2, lat = 1), class = "countryatlas_error")
})

test_that("locate_country snaps coastal points but leaves open ocean NA", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  # New York sits ~0.5 km outside the coarse 110m US coastline: the default
  # tolerance snaps it to the US, strict mode (tolerance_km = 0) does not.
  expect_equal(locate_country(lon = -74.0, lat = 40.7)$iso3c, "USA")
  expect_true(is.na(locate_country(lon = -74.0, lat = 40.7, tolerance_km = 0)$iso3c))
  # Open ocean is hundreds of km from land, so it stays NA even with snapping.
  expect_true(is.na(locate_country(lon = -30, lat = -30)$iso3c))
})

test_that("country_borders returns a tidy edge list", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
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
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  edges <- country_borders()
  expect_false(any(edges$iso3c_a == edges$iso3c_b))
})

test_that("neighbors lists a country's bordering countries", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  nbr <- neighbors("France")
  expect_s3_class(nbr, "tbl_df")
  expect_true("DEU" %in% nbr$neighbor)
  expect_true("ESP" %in% nbr$neighbor)
})

test_that("neighbors returns zero rows for islands", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  nbr <- neighbors("Japan")
  expect_equal(nrow(nbr), 0)
})

test_that("locate_country names Kosovo (XKX has no countrycode row)", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  out <- locate_country(lon = 20.9, lat = 42.6, add = c("country", "continent"))
  expect_equal(out$iso3c, "XKX")
  expect_equal(out$country, "Kosovo")
  expect_equal(out$continent, "Europe")
})

test_that("country_borders names every endpoint, Kosovo included", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  edges <- country_borders()
  expect_false(anyNA(edges$country_a))
  expect_false(anyNA(edges$country_b))
  xkx <- edges[edges$iso3c_a == "XKX" | edges$iso3c_b == "XKX", ]
  expect_gt(nrow(xkx), 0)
})

test_that("world_geometry('coastline') works in every projection", {
  # Two Natural Earth rings are invalid once projected, and st_union() (unlike
  # the predicates) refuses them outright: the coastline used to error with
  # "TopologyException: side location conflict" in all but plate_carree.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
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
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  eur <- world_geometry("countries", geometry = "sf",
                        region = c(-10, 35, 30, 60))
  expect_s3_class(eur, "sf")
  expect_gt(nrow(eur), 10)
  expect_lt(nrow(eur), 100)
  expect_true("FRA" %in% eur$iso3c)
  expect_false("AUS" %in% eur$iso3c)
})

test_that("polygon_centroids returns one centroid per iso3c", {
  # Bug 3.3: PRT / ESP / BES must each produce ONE row, not multiple.
  skip_if_not_installed("maps")
  poly <- countryatlas:::world_polygons()
  cent <- countryatlas:::polygon_centroids(poly)
  # Every iso3c appears exactly once
  expect_equal(anyDuplicated(cent$iso3c), 0)
  # Known multi-piece countries must have exactly one centroid row
  expect_equal(nrow(dplyr::filter(cent, .data$iso3c == "PRT")), 1)
  expect_equal(nrow(dplyr::filter(cent, .data$iso3c == "ESP")), 1)
  expect_equal(nrow(dplyr::filter(cent, .data$iso3c == "BES")), 1)
})

test_that("attach_geometry threads custom overrides into geometry matching", {
  # Regression: world_data(overrides=) / attach_geometry(overrides=) were
  # accepted but silently ignored -- the geometry backend always matched with
  # the default override set. A custom set must now actually take effect.
  skip_if_not_installed("maps")
  poly <- attach_geometry(
    data.frame(iso3c = "ZZ1", value = 42),
    geometry = "polygon",
    overrides = wdj_overrides(c(Greenland = "ZZ1"))
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
  skip_if_not_installed("maps")
  df <- data.frame(iso3c = c("USA", "ZZZ"), value = c(1, 2))
  out <- attach_geometry(df, geometry = "polygon")
  expect_true("USA" %in% out$iso3c)
  expect_false("ZZZ" %in% out$iso3c)      # silent, as documented
  expect_true(all(!is.na(out$long)))
})

test_that("sf coverage is monotone in scale, and medium beats small", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
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
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
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
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
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
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
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
  # ?world_geometry used to call all four azimuthal projections "hemispheric",
  # which is true of "orthographic" (+proj=ortho) alone. The other three are
  # Lambert azimuthal equal-area, which images the whole globe with the far side
  # stretched around the rim -- nothing comes back empty. The docs now say so,
  # and a reader who filters on st_is_empty() depends on the difference.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")

  n_empty <- function(projection) {
    g <- world_geometry("countries", geometry = "sf", projection = projection)
    sum(sf::st_is_empty(sf::st_geometry(g)))
  }
  expect_gt(n_empty("orthographic"), 0L)
  for (pr in c("azimuthal_equal_area", "north_polar", "south_polar")) {
    expect_identical(n_empty(pr), 0L, info = pr)
  }
  # Equal-area really is equal-area: New Zealand keeps its size on the far rim.
  nz <- world_geometry("countries", geometry = "sf", projection = "north_polar")
  nz <- nz[!is.na(nz$iso3c) & nz$iso3c == "NZL", ]
  expect_lt(abs(as.numeric(sf::st_area(nz)) / 1e12 - 0.27), 0.15)
})

test_that("the ISO-less Natural Earth features are documented", {
  # ?world_geometry names these as the rows that come back with iso3c NA; if a
  # future rnaturalearth changes the set, the doc has to change with it.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  g <- world_geometry("countries", geometry = "sf", scale = "small")
  expect_identical(sort(g$name_long[is.na(g$iso3c)]), "Somaliland")
})

test_that("sf centroid columns are projected units, as documented", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
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
  # The ocean layer was a 2-point, zero-area polygon in every projection, and
  # nothing caught it: st_bbox() reported the stored extent rather than
  # recomputing it, so every diagnostic looked healthy. Measure the geometry
  # itself, for every layer.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
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
  # Natural Earth hands over 177 uniform MULTIPOLYGONs, but
  # st_break_antimeridian() runs an st_intersection internally that collapses a
  # single-part MULTIPOLYGON to a POLYGON -- leaving 148 POLYGON + 29
  # MULTIPOLYGON, i.e. an sfc_GEOMETRY column. sf::st_coordinates() is not
  # implemented for that, so pulling vertices out of world_geometry("countries")
  # failed, in every projection including the default.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
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
  # Orthographic hides half the globe, so those countries have no image. The
  # empty geometries are correct; recorded here so the resulting
  # st_coordinates() limitation is not mistaken for the bug fixed above.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
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
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
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
  # It used to pass a fixed dTolerance of (1 - keep) * 10000, i.e. metres
  # whatever the CRS: 9 km on a projected frame, which barely simplified
  # anything, and 9000 *degrees* on a lon/lat one, where only
  # preserveTopology kept the result usable at all.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
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
  # The invariant broke twice: st_break_antimeridian() downgraded the source
  # column (fixed in get_world_sf), and then simplify_geometry() undid the fix
  # downstream. Check the whole surface rather than the two known sites.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
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
