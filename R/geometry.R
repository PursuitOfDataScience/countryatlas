# Geometry backends & utilities -------------------------------------------------

# The projections countryatlas knows how to build a CRS for.
wdj_projections <- function() {
  c("equal_earth", "robinson", "mollweide", "natural_earth", "plate_carree",
    "mercator", "winkel_tripel", "eckert4", "gall_peters", "orthographic",
    "azimuthal_equal_area", "north_polar", "south_polar")
}

# Map projection -> a CRS usable by sf::st_transform / ggplot2::coord_sf.
# `recenter` shifts the central meridian (e.g. 150 for a Pacific-centred map);
# `lat0` sets the central latitude for the azimuthal projections (orthographic).
wdj_crs <- function(projection = "equal_earth", recenter = NULL, lat0 = NULL) {
  projection <- match.arg(projection, wdj_projections())
  lon0 <- recenter %||% 0
  proj4 <- switch(
    projection,
    equal_earth          = "+proj=eqearth",
    robinson             = "+proj=robin",
    mollweide            = "+proj=moll",
    natural_earth        = "+proj=natearth",
    # Plate carree is equirectangular (+proj=eqc), NOT geographic (+proj=longlat).
    plate_carree         = "+proj=eqc +lat_ts=0",
    mercator             = "+proj=merc",
    winkel_tripel        = "+proj=wintri",
    eckert4              = "+proj=eck4",
    gall_peters          = "+proj=cea +lat_ts=45",
    orthographic         = paste0("+proj=ortho +lat_0=", lat0 %||% 20),
    azimuthal_equal_area = paste0("+proj=laea +lat_0=", lat0 %||% 0),
    north_polar          = "+proj=laea +lat_0=90",
    south_polar          = "+proj=laea +lat_0=-90"
  )
  paste0(proj4, " +lon_0=", lon0, " +datum=WGS84 +units=m +no_defs")
}

# coord_sf() for one of our projections.
#
# ggplot2's coord_sf() builds a graticule for the target CRS. Under PROJ's
# Winkel Tripel some graticule segments collapse to a single point, and GEOS
# rejects those outright ("IllegalArgumentException: point array must contain
# 0 or >1 elements") -- so every winkel_tripel map failed at build time even
# though the geometry itself projects fine. theme_world_map() blanks
# panel.grid, so the graticule is invisible in these maps anyway and skipping
# it costs nothing. Every other projection keeps the default graticule.
wdj_coord_sf <- function(projection = "equal_earth", recenter = NULL,
                         lat0 = NULL) {
  crs <- wdj_crs(projection, recenter, lat0)
  if (identical(projection, "winkel_tripel")) {
    return(ggplot2::coord_sf(crs = crs, datum = NA))
  }
  ggplot2::coord_sf(crs = crs)
}

# Map a Natural Earth scale word to the package code understood by rnaturalearth.
ne_scale <- function(scale = c("small", "medium", "large")) {
  scale <- match.arg(scale)
  switch(scale, small = 110, medium = 50, large = 10)
}

# Region presets: continents, common groups and bounding boxes resolve to a set
# of iso3c codes used to subset geometry. Returns NULL for "world".
resolve_region <- function(region) {
  if (is.null(region)) return(NULL)
  # A bounding box: c(xmin, ymin, xmax, ymax).
  if (is.numeric(region) && length(region) == 4L) {
    return(structure(region, class = "wdj_bbox"))
  }
  region <- as.character(region)
  continents <- c("Africa", "Americas", "Asia", "Europe", "Oceania")
  if (length(region) == 1L && region %in% continents) {
    cl <- countrycode::codelist
    return(cl$iso3c[!is.na(cl$continent) & cl$continent == region])
  }
  # A named group (EU, OECD, ...).
  groups <- unique(country_groups_tbl$group)
  if (length(region) == 1L && region %in% groups) {
    return(country_groups(region)$iso3c)
  }
  # Otherwise treat as a vector of iso3c codes (or names to be standardised).
  if (all(nchar(region) == 3L & toupper(region) == region)) {
    return(toupper(region))
  }
  wdj_to_iso3c(region)
}

# --- Polygon backend (maps / ggplot2::map_data) -------------------------------

# Build map_data("world") as a tibble with iso3c/iso2c attached via overrides.
# Memoised because map_data is deterministic and not free to rebuild.
build_world_polygons <- function(overrides = wdj_overrides()) {
  need_pkg("maps", "for the polygon geometry backend")
  md <- ggplot2::map_data("world")
  md <- tibble::as_tibble(md)
  iso3c <- wdj_to_iso3c(md$region, origin = "country.name",
                        custom_match = overrides)
  md$iso3c <- iso3c
  md$iso2c <- suppressWarnings(
    countrycode::countrycode(iso3c, "iso3c", "iso2c", warn = FALSE)
  )
  md <- apply_code_fallback(md)
  md
}

world_polygons <- memoise::memoise(build_world_polygons)

get_world_polygons <- function(region = NULL, overrides = wdj_overrides()) {
  md <- world_polygons(overrides)
  iso <- resolve_region(region)
  if (is.null(iso)) return(md)
  if (inherits(iso, "wdj_bbox")) {
    bb <- unclass(iso)
    return(dplyr::filter(md, long >= bb[1], lat >= bb[2],
                         long <= bb[3], lat <= bb[4]))
  }
  dplyr::filter(md, .data$iso3c %in% iso)
}

# --- sf backend (rnaturalearth) -----------------------------------------------

build_world_sf <- function(scale = "small", overrides = wdj_overrides()) {
  need_pkg(c("sf", "rnaturalearth", "rnaturalearthdata"),
           "for the sf geometry backend")
  ne <- rnaturalearth::ne_countries(scale = ne_scale(scale), returnclass = "sf")
  # iso_a3 is -99 / NA for France, Norway, Kosovo, ... so fall back to
  # countrycode on admin / sovereignt names. Guarded by a regression test.
  iso3c <- ne$iso_a3
  iso3c[iso3c %in% c("-99", "-099", "")] <- NA
  fallback_name <- ne$admin %||% ne$sovereignt %||% ne$name_long
  needs <- is.na(iso3c)
  if (any(needs)) {
    iso3c[needs] <- wdj_to_iso3c(fallback_name[needs], origin = "country.name",
                                 custom_match = overrides)
  }
  ne$iso3c <- iso3c
  ne$iso2c <- suppressWarnings(
    countrycode::countrycode(iso3c, "iso3c", "iso2c", warn = FALSE)
  )
  keep <- c("iso3c", "iso2c", "name_long", "geometry")
  keep <- intersect(keep, names(ne))
  ne <- ne[, keep]
  ne <- apply_code_fallback(ne)
  ne
}

# Memoise per-scale.
.world_sf_cache <- new.env(parent = emptyenv())

get_world_sf <- function(scale = "small", region = NULL,
                         projection = "equal_earth", recenter = NULL,
                         project = TRUE, overrides = wdj_overrides()) {
  need_pkg("sf", "for the sf geometry backend")
  # Cache the default-overrides geometry (the common case); a custom override
  # set rebuilds uncached so the caller's overrides actually take effect.
  if (identical(overrides, wdj_overrides())) {
    key <- paste0("scale_", scale)
    if (is.null(.world_sf_cache[[key]])) {
      .world_sf_cache[[key]] <- build_world_sf(scale, overrides)
    }
    ne <- .world_sf_cache[[key]]
  } else {
    ne <- build_world_sf(scale, overrides)
  }

  iso <- resolve_region(region)
  if (!is.null(iso)) {
    if (inherits(iso, "wdj_bbox")) {
      bb <- unclass(iso)
      bbox <- sf::st_bbox(c(xmin = bb[1], ymin = bb[2], xmax = bb[3], ymax = bb[4]),
                          crs = sf::st_crs(4326))
      # Natural Earth has a couple of self-intersecting rings that the strict
      # S2 engine (the default on unprojected geometry) rejects outright, so
      # cropping to a bounding box used to error. Use GEOS's planar clip
      # instead -- exactly as country_borders() / locate_country() do.
      use_s2 <- sf::sf_use_s2()
      on.exit(quietly_sf(sf::sf_use_s2(use_s2)), add = TRUE)
      ne <- quietly_sf(suppressWarnings({
        sf::sf_use_s2(FALSE)
        sf::st_crop(ne, bbox)
      }))
    } else {
      ne <- ne[!is.na(ne$iso3c) & ne$iso3c %in% iso, ]
    }
  }

  # Antimeridian-safe before projecting so Russia/Fiji/NZ stop streaking.
  # (st_break_antimeridian's internal st_intersection notes that attributes are
  # assumed spatially constant -- expected and harmless here, so suppress it.)
  ne <- suppressWarnings(
    tryCatch(sf::st_break_antimeridian(ne, lon_0 = recenter %||% 0),
             error = function(e) ne)
  )
  if (isTRUE(project)) {
    ne <- sf::st_transform(ne, crs = wdj_crs(projection, recenter))
  }
  ne
}

#' Geometry without the data
#'
#' Sometimes you just want the canvas: country polygons, label-ready centroids,
#' coastlines, internal borders, a graticule or an ocean rectangle -- already
#' projected, region-subset and antimeridian-safe. This is the building block
#' the plotting functions sit on, exposed for power users.
#'
#' @param what What to return: `"countries"` (default), `"centroids"`,
#'   `"coastline"`, `"borders"`, `"graticule"` or `"ocean"`.
#' @param geometry `"polygon"` (a tibble of `long`/`lat`/`group`) or `"sf"`.
#' @param scale Natural Earth resolution for the `sf` backend:
#'   `"small"` (110m), `"medium"` (50m) or `"large"` (10m).
#' @param region Optional subset: a continent, a group name, a vector of `iso3c`
#'   codes, or a bounding box `c(xmin, ymin, xmax, ymax)`.
#' @param projection Projection for the `sf` backend (see [world_map()]).
#' @param recenter Optional central meridian for a recentred map (e.g. `150`).
#'
#' @return A tibble (polygon backend) or `sf` object (sf backend).
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   head(world_geometry("countries", geometry = "polygon"))
#' }
#' }
world_geometry <- function(what = c("countries", "centroids", "coastline",
                                    "borders", "graticule", "ocean"),
                           geometry = c("polygon", "sf"),
                           scale = "small",
                           region = NULL,
                           projection = "equal_earth",
                           recenter = NULL) {
  what <- match.arg(what)
  geometry <- match.arg(geometry)

  if (geometry == "polygon") {
    if (!what %in% c("countries", "centroids")) {
      wdj_abort(c(
        "{.val {what}} is only available with {.code geometry = \"sf\"}.",
        "i" = "The polygon backend supports {.val countries} and {.val centroids}."
      ))
    }
    poly <- get_world_polygons(region)
    if (what == "countries") return(poly)
    return(polygon_centroids(poly))
  }

  # sf backend.
  need_pkg("sf", "for the sf geometry backend")
  countries <- get_world_sf(scale, region, projection, recenter)
  switch(
    what,
    countries = countries,
    centroids = sf_centroids(countries),
    # A couple of Natural Earth rings are invalid (self-intersecting), and
    # st_union() -- unlike the predicates -- refuses to work with them
    # ("TopologyException: side location conflict"). Repair first so the
    # coastline is available in every projection, not just the lucky ones.
    coastline = sf::st_cast(
      sf::st_union(quietly_sf(suppressWarnings(sf::st_make_valid(countries)))),
      "MULTILINESTRING"
    ),
    borders   = sf::st_cast(countries, "MULTILINESTRING", warn = FALSE),
    graticule = sf::st_transform(
      sf::st_graticule(),
      crs = wdj_crs(projection, recenter)
    ),
    ocean = {
      box <- sf::st_as_sfc(sf::st_bbox(c(xmin = -180, ymin = -90, xmax = 180, ymax = 90),
                                       crs = sf::st_crs(4326)))
      box <- suppressWarnings(
        tryCatch(sf::st_break_antimeridian(box, lon_0 = recenter %||% 0),
                 error = function(e) box)
      )
      sf::st_transform(box, crs = wdj_crs(projection, recenter))
    }
  )
}

# Spherical polygon area (km^2) of one lon/lat ring. Used to pick a country's
# largest piece so the centroid is stable and antimeridian-safe (a bounding-box
# midpoint over *all* pieces lands the US/Fiji/NZ label in the wrong ocean).
ring_area_km2 <- function(lon, lat) {
  ok <- is.finite(lon) & is.finite(lat)
  lon <- lon[ok]; lat <- lat[ok]
  n <- length(lon)
  if (n < 3L) return(0)
  R <- 6371.0088; d2r <- pi / 180
  lon <- lon * d2r; lat <- lat * d2r
  i <- seq_len(n); j <- c(2:n, 1L)
  abs(sum((lon[j] - lon[i]) * (2 + sin(lat[i]) + sin(lat[j]))) * R^2 / 2)
}

# One centroid per iso3c from polygon rows: the bounding-box midpoint of the
# country's *largest* piece. One row per country (overrides map several map_data
# names -- Azores/Madeira -> PRT -- to one iso3c, so grouping must collapse them,
# or downstream joins in bubble_map()/flow_map() fan out).
polygon_centroids <- function(poly) {
  poly %>%
    dplyr::filter(!is.na(.data$iso3c)) %>%
    dplyr::group_by(.data$iso3c, .data$group) %>%
    dplyr::summarise(
      g_lon = mean(range(.data$long, na.rm = TRUE)),
      g_lat = mean(range(.data$lat, na.rm = TRUE)),
      g_area = ring_area_km2(.data$long, .data$lat),
      .groups = "drop_last"
    ) %>%
    dplyr::summarise(
      centroid_lon = .data$g_lon[which.max(.data$g_area)],
      centroid_lat = .data$g_lat[which.max(.data$g_area)],
      .groups = "drop"
    )
}

# Label-safe centroids for the sf backend: st_point_on_surface keeps the point
# *inside* the country.
sf_centroids <- function(x) {
  need_pkg("sf", "for centroid computation")
  pts <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(x)))
  coords <- sf::st_coordinates(pts)
  out <- sf::st_drop_geometry(x)
  out$centroid_lon <- coords[, 1]
  out$centroid_lat <- coords[, 2]
  out$geometry <- pts
  sf::st_as_sf(out)
}

#' Attach geometry to a country-level table
#'
#' The bridge between a one-row-per-country table (e.g. from [country_data()])
#' and plotting: bolts polygon or `sf` geometry onto your data, keyed on
#' `iso3c`.
#'
#' @param data A data frame with an `iso3c` (or `by`) column.
#' @param by The join key (default `"iso3c"`).
#' @param geometry `"polygon"` (default) or `"sf"`.
#' @param scale Natural Earth resolution for the `sf` backend.
#' @param region Optional region subset (see [world_geometry()]).
#' @param projection,recenter Projection options for the `sf` backend.
#' @param overrides Name -> iso3c overrides applied when matching the geometry
#'   backend's country names (default [wdj_overrides()]). Pass a custom set
#'   built with [wdj_overrides()] to add your own.
#'
#' @return For `"polygon"`, a tibble with `long`/`lat`/`group` plus your
#'   columns. For `"sf"`, an `sf` object.
#' @export
#' @examples
#' \donttest{
#' df <- data.frame(iso3c = c("USA", "CAN"), value = c(1, 2))
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   attach_geometry(df, geometry = "polygon")
#' }
#' }
attach_geometry <- function(data,
                            by = "iso3c",
                            geometry = c("polygon", "sf"),
                            scale = "small",
                            region = NULL,
                            projection = "equal_earth",
                            recenter = NULL,
                            overrides = wdj_overrides()) {
  geometry <- match.arg(geometry)
  if (!by %in% names(data)) {
    wdj_abort("{.arg data} must contain the join column {.val {by}}.")
  }
  data <- tibble::as_tibble(data)

  if (geometry == "polygon") {
    poly <- get_world_polygons(region, overrides = overrides)
    # geometry on the left preserves all polygon rows; values fill in.
    drop <- setdiff(intersect(names(poly), names(data)), by)
    poly <- poly[, setdiff(names(poly), drop), drop = FALSE]
    out <- dplyr::left_join(poly, data, by = by)
    return(out)
  }

  geom <- get_world_sf(scale, region, projection, recenter, overrides = overrides)
  drop <- setdiff(intersect(names(geom), names(data)), by)
  geom <- geom[, setdiff(names(geom), drop), drop = FALSE]
  dplyr::left_join(geom, data, by = by)
}

#' Tag coordinates with the country that contains them
#'
#' Point-in-polygon lookup: given longitude / latitude vectors (or an `sf` POINT
#' object), return the `iso3c` of the country each point falls in -- the bridge
#' for getting point data (events, stations, observations) onto the country
#' spine so it can be joined, aggregated and mapped like everything else.
#'
#' @param lon,lat Numeric vectors of longitude / latitude (recycled together;
#'   ignored if `points` is supplied).
#' @param points Optional `sf` POINT object to use instead of `lon`/`lat`.
#' @param scale Natural Earth resolution for the lookup geometry.
#' @param add Extra attributes to return alongside `iso3c` (any
#'   [convert_country()] destination, e.g. `"country"`, `"continent"`).
#' @param tolerance_km Snap an unmatched point to the nearest country when it
#'   lies within this many kilometres of one (default `25`). Coarse (110m)
#'   coastlines place some genuinely-onshore coastal points just outside their
#'   country (New York sits ~0.5 km beyond the simplified US coast); this
#'   rescues them while leaving open-ocean points `NA` (the nearest land is
#'   hundreds of km away). Set `0` for a strict point-in-polygon lookup.
#'
#' @return A tibble with one row per point: `iso3c` plus any `add` columns
#'   (`NA` for points that fall in no country, e.g. open ocean).
#' @export
#' @examples
#' \dontrun{
#' locate_country(lon = c(2.35, -74.0), lat = c(48.85, 40.7))  # Paris, NYC
#' }
locate_country <- function(lon = NULL, lat = NULL, points = NULL,
                           scale = "small", add = "country",
                           tolerance_km = 25) {
  need_pkg("sf", "for locate_country()")
  geom <- get_world_sf(scale = scale, project = FALSE)        # lon/lat (EPSG:4326)
  if (is.null(points)) {
    if (is.null(lon) || is.null(lat) || length(lon) != length(lat)) {
      wdj_abort("Supply equal-length {.arg lon} and {.arg lat}, or an {.arg points} sf object.")
    }
    points <- sf::st_as_sf(data.frame(lon = lon, lat = lat),
                           coords = c("lon", "lat"), crs = 4326)
  } else {
    points <- sf::st_transform(points, 4326)
  }
  # Natural Earth rings can be invalid as spherical geometry, which the strict
  # s2 engine that st_intersects() uses by default on unprojected geometry
  # rejects outright (erroring on the WKB->s2 conversion). Fall back to GEOS's
  # planar predicate -- plenty accurate for point-in-country -- exactly as
  # country_borders() does; quietly_sf() also swallows the s2 toggle's stderr note.
  use_s2 <- sf::sf_use_s2()
  on.exit(quietly_sf(sf::sf_use_s2(use_s2)), add = TRUE)
  idx <- quietly_sf(suppressWarnings({
    sf::sf_use_s2(FALSE)
    hit <- sf::st_intersects(points, geom)
    idx <- vapply(hit, function(h) if (length(h)) h[[1]] else NA_integer_, integer(1))
    # A coarse coastline (110m) can place a genuinely-onshore point just outside
    # its country (New York is ~0.5 km beyond the simplified US coast). Snap an
    # unmatched point to the nearest country when it is within tolerance_km; open
    # ocean stays NA because the nearest land is hundreds of km away.
    miss <- which(is.na(idx))
    if (length(miss) && tolerance_km > 0) {
      near <- sf::st_nearest_feature(points[miss, ], geom)
      link <- sf::st_nearest_points(points[miss, ], geom[near, ], by_element = TRUE)
      dkm <- vapply(seq_along(near), function(i) {
        m <- sf::st_coordinates(link[i])
        haversine_km(m[1, 1], m[1, 2], m[2, 1], m[2, 2])
      }, numeric(1))
      idx[miss] <- ifelse(dkm <= tolerance_km, near, NA_integer_)
    }
    idx
  }))
  iso3c <- geom$iso3c[idx]
  out <- tibble::tibble(iso3c = iso3c)
  for (a in setdiff(add, "iso3c")) {
    out[[a]] <- convert_country(iso3c, to = a, from = "iso3c", warn = FALSE)
  }
  out
}

#' Country adjacency (shared land borders)
#'
#' Which countries share a land border with which, as a tidy edge list --
#' built from polygon topology ([sf::st_touches()]), so it reflects the same
#' curated geometry as the rest of the package. Powers [neighbors()]. Convert
#' to a graph with e.g. `igraph::graph_from_data_frame(country_borders(),
#' directed = FALSE)` if you need one.
#'
#' @param scale Natural Earth resolution to compute adjacency from. Coarser
#'   scales simplify small slivers and may miss a handful of short borders.
#' @param region Optional region subset (see [world_geometry()]); a pair is
#'   only reported when both countries remain in the subset.
#'
#' @return A tibble, one row per bordering pair: `iso3c_a`, `country_a`,
#'   `iso3c_b`, `country_b`. Each unordered pair appears once, with
#'   `iso3c_a <= iso3c_b` alphabetically.
#' @export
#' @examples
#' \dontrun{
#' country_borders()
#' country_borders(region = "Europe")
#' }
country_borders <- function(scale = "small", region = NULL) {
  need_pkg("sf", "for country_borders()")
  geom <- get_world_sf(scale = scale, region = region, project = FALSE)
  geom <- geom[!is.na(geom$iso3c), ]
  # A handful of Natural Earth rings are self-intersecting at this
  # resolution; the strict S2 engine st_touches() uses by default on
  # unprojected geometry rejects them outright. GEOS's planar predicate is
  # more forgiving and plenty accurate at country scale. The s2 toggle (and
  # st_touches()'s own internal validity fallback) print diagnostic notices
  # straight to stderr, bypassing R's message() condition system entirely --
  # quietly_sf() catches those too, where suppressMessages() can't.
  use_s2 <- sf::sf_use_s2()
  on.exit(quietly_sf(sf::sf_use_s2(use_s2)), add = TRUE)
  touching <- quietly_sf({
    sf::sf_use_s2(FALSE)
    sf::st_touches(geom)
  })
  n <- nrow(geom)
  # Some countries (Cyprus, divided between the Republic and the de facto
  # Northern Cyprus) are more than one geometry row sharing one iso3c, and
  # those pieces can touch each other -- exclude same-iso3c matches so a
  # country never "borders" itself. st_touches() is symmetric, so every
  # cross-country pair is collected from both sides at this point; that is
  # resolved below rather than by row position, since row position only maps
  # 1:1 to iso3c for countries that are a single piece.
  pairs <- lapply(seq_len(n), function(i) {
    js <- touching[[i]]
    js <- js[geom$iso3c[js] != geom$iso3c[i]]
    if (!length(js)) return(NULL)
    tibble::tibble(iso3c_a = geom$iso3c[i], iso3c_b = geom$iso3c[js])
  })
  out <- dplyr::bind_rows(pairs)
  if (!nrow(out)) {
    return(tibble::tibble(iso3c_a = character(), country_a = character(),
                          iso3c_b = character(), country_b = character()))
  }
  # Canonicalise to one row per unordered pair (alphabetical order), which
  # collapses both the symmetric double-count and any duplicate-iso3c rows.
  out <- dplyr::distinct(tibble::tibble(
    iso3c_a = pmin(out$iso3c_a, out$iso3c_b),
    iso3c_b = pmax(out$iso3c_a, out$iso3c_b)
  ))
  out$country_a <- convert_country(out$iso3c_a, to = "country", from = "iso3c", warn = FALSE)
  out$country_b <- convert_country(out$iso3c_b, to = "country", from = "iso3c", warn = FALSE)
  out[, c("iso3c_a", "country_a", "iso3c_b", "country_b")]
}

#' A country's neighbours
#'
#' Which countries border a given country (or countries) -- a vectorised
#' lookup built on [country_borders()].
#'
#' @param x A vector of country names or codes.
#' @param origin How to read `x` (default `"country.name"`).
#' @param scale Natural Earth resolution to compute adjacency from.
#'
#' @return A tibble with one row per (`iso3c`, `neighbor`) pair: the queried
#'   country's `iso3c`, and each bordering country's `iso3c` and `country`
#'   name (`neighbor`, `neighbor_country`). Countries with no land border
#'   (islands, e.g. Japan, Madagascar) return zero rows.
#' @export
#' @examples
#' \dontrun{
#' neighbors("France")
#' neighbors(c("FRA", "JPN"), origin = "iso3c")
#' }
neighbors <- function(x, origin = "country.name", scale = "small") {
  iso <- wdj_to_iso3c(x, origin = origin)
  borders <- country_borders(scale = scale)
  sym <- dplyr::bind_rows(
    tibble::tibble(iso3c = borders$iso3c_a, neighbor = borders$iso3c_b,
                   neighbor_country = borders$country_b),
    tibble::tibble(iso3c = borders$iso3c_b, neighbor = borders$iso3c_a,
                   neighbor_country = borders$country_a)
  )
  dplyr::filter(sym, .data$iso3c %in% iso)
}

#' Global Moran's I (spatial autocorrelation)
#'
#' Do neighbouring countries have similar values? Global Moran's I on the
#' country spine, using the [country_borders()] land-border adjacency as the
#' spatial weights (row-standardised), with a permutation pseudo-p-value. No
#' `spdep` required: at ~200 countries the dense arithmetic is trivial, and
#' reusing the package's own adjacency keeps the weights consistent with the
#' maps. Countries with no land border in the data (islands) carry no weight
#' and are excluded.
#'
#' @param data A country-level data frame with `iso3c` (map-ready frames are
#'   reduced to one row per country).
#' @param value The value column (unquoted).
#' @param scale Natural Earth resolution for the adjacency (see
#'   [country_borders()]).
#' @param n_perm Number of permutations for the pseudo-p-value (default `999`;
#'   use `0` to skip the test).
#'
#' @return A one-row tibble: `i` (observed Moran's I), `expected`
#'   (\eqn{-1/(n-1)} under no autocorrelation), `n` (countries used),
#'   `n_links` (border pairs among them) and `p_value` (one-sided,
#'   \eqn{P(I_{perm} \ge I_{obs})}; positive autocorrelation is the standard
#'   alternative). Set a seed beforehand for a reproducible `p_value`.
#' @export
#' @examples
#' \dontrun{
#' snap <- countryatlas::world_snapshot$countries
#' set.seed(42)
#' morans_i(snap, gdp_per_capita)   # GDP clusters strongly in space
#' }
morans_i <- function(data, value, scale = "small", n_perm = 999) {
  need_pkg("sf", "for morans_i() (adjacency comes from country_borders())")
  val_name <- rlang::as_name(rlang::enquo(value))
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  df <- dplyr::distinct(tibble::as_tibble(data), .data$iso3c, .keep_all = TRUE)
  df <- df[!is.na(df$iso3c) & is.finite(df[[val_name]]), ]

  borders <- country_borders(scale = scale)
  b <- borders[borders$iso3c_a %in% df$iso3c & borders$iso3c_b %in% df$iso3c, ]
  # Countries with at least one neighbour in the data.
  iso <- sort(unique(c(b$iso3c_a, b$iso3c_b)))
  n <- length(iso)
  if (n < 3L) {
    wdj_abort(c(
      "Not enough bordering countries with data to compute Moran's I.",
      "i" = "Got {n}; need at least 3."
    ))
  }
  W <- matrix(0, n, n, dimnames = list(iso, iso))
  W[cbind(b$iso3c_a, b$iso3c_b)] <- 1
  W[cbind(b$iso3c_b, b$iso3c_a)] <- 1
  W <- W / rowSums(W)   # row-standardise; every row has >= 1 neighbour

  x <- df[[val_name]][match(iso, df$iso3c)]
  moran_stat <- function(x) {
    z <- x - mean(x)
    # With row-standardised weights, sum(W) == n, so the n/S0 factor is 1.
    (n / sum(W)) * sum(W * outer(z, z)) / sum(z^2)
  }
  i_obs <- moran_stat(x)

  p_value <- NA_real_
  n_perm <- max(0L, as.integer(n_perm))
  if (n_perm > 0L) {
    i_perm <- vapply(seq_len(n_perm), function(k) moran_stat(sample(x)),
                     numeric(1))
    p_value <- (1 + sum(i_perm >= i_obs)) / (n_perm + 1)
  }
  tibble::tibble(
    i = i_obs,
    expected = -1 / (n - 1),
    n = n,
    n_links = nrow(b),
    p_value = p_value
  )
}

#' Great-circle distance between two countries
#'
#' Haversine distance (km) between two countries' centroids -- the lightweight
#' companion to [country_borders()] for "how far apart" rather than "do they
#' touch". Works from the bundled [country_meta] centroids, so unlike most of
#' the spatial toolkit it needs neither `sf` nor the network.
#'
#' @param a,b Vectors of country names or codes (recycled against each other).
#' @param origin How to read `a`/`b` (default `"country.name"`).
#'
#' @return A numeric vector of great-circle distances in kilometres (`NA` for
#'   any country that doesn't resolve to a known centroid).
#' @export
#' @examples
#' distance_between("France", "Germany")
#' distance_between("USA", c("Canada", "Mexico"))
distance_between <- function(a, b, origin = "country.name") {
  iso_a <- wdj_to_iso3c(a, origin = origin)
  iso_b <- wdj_to_iso3c(b, origin = origin)
  meta <- country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
  ca <- meta[match(iso_a, meta$iso3c), ]
  cb <- meta[match(iso_b, meta$iso3c), ]
  haversine_km(ca$centroid_lon, ca$centroid_lat, cb$centroid_lon, cb$centroid_lat)
}

# Haversine great-circle distance (km) between lon/lat points (vectorised,
# recycled the usual R way). Shares the Earth radius constant with
# ring_area_km2() for consistency.
haversine_km <- function(lon1, lat1, lon2, lat2) {
  R <- 6371.0088
  d2r <- pi / 180
  dlat <- (lat2 - lat1) * d2r
  dlon <- (lon2 - lon1) * d2r
  a <- sin(dlat / 2)^2 + cos(lat1 * d2r) * cos(lat2 * d2r) * sin(dlon / 2)^2
  2 * R * asin(pmin(1, sqrt(a)))
}
