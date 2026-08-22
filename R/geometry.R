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
  # PROJ refuses |lat_0| >= 90 outright, and the resulting invalid CRS only
  # surfaced later as coord_sf()'s "crs not found: is it missing?". The central
  # meridian is allowed a full turn either way because spin_globe() sweeps
  # recenter from 0 to just under 360.
  if (!is.null(recenter)) check_number(recenter, "recenter", lo = -360, hi = 360)
  if (!is.null(lat0)) check_number(lat0, "lat0", lo = -90, hi = 90)
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
    orthographic         = paste0("+proj=ortho +lat_0=", fmt_num(lat0 %||% 20)),
    azimuthal_equal_area = paste0("+proj=laea +lat_0=", fmt_num(lat0 %||% 0)),
    north_polar          = "+proj=laea +lat_0=90",
    south_polar          = "+proj=laea +lat_0=-90"
  )
  paste0(proj4, " +lon_0=", fmt_num(lon0), " +datum=WGS84 +units=m +no_defs")
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
# Integer literals, not doubles: rnaturalearth builds the name of its data
# object by pasting this number ("countries" + 110), and under
# a negative scipen a double 110 formats as "1.1e+02", so the lookup failed
# with "'countries1.1e+02' is not an exported object". Integers are immune.
ne_scale <- function(scale = c("small", "medium", "large")) {
  scale <- match.arg(scale)
  switch(scale, small = 110L, medium = 50L, large = 10L)
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
  groups <- unique(countryatlas::country_groups_tbl$group)
  if (length(region) == 1L && region %in% groups) {
    return(country_groups(region)$iso3c)
  }
  # Otherwise treat as a vector of iso3c codes (or names to be standardised).
  # Codes are recognised case-insensitively: ISO alpha-3 is canonically
  # uppercase, but wdj_to_iso3c(origin = "iso3c") accepts any case, and falling
  # straight through to name matching resolved some lowercase codes ("usa", via
  # countrycode's case-insensitive name regex) while silently dropping others
  # ("can"), so a lowercase vector lost countries without saying so.
  up <- ascii_upper(trimws(region))
  if (all(nchar(up) == 3L) && all(up %in% wdj_known_iso3c())) {
    return(up)
  }
  # An all-uppercase 3-letter vector is still taken at face value even when a
  # code is unknown, so an unrecognised code yields an empty subset rather than
  # being reinterpreted as a country name.
  if (all(nchar(region) == 3L & ascii_upper(region) == region)) {
    return(ascii_upper(region))
  }
  wdj_to_iso3c(region)
}

# --- Polygon backend (maps / ggplot2::map_data) -------------------------------

# Build map_data("world") as a tibble with iso3c/iso2c attached via overrides.
# Memoised because map_data is deterministic and not free to rebuild.
build_world_polygons <- function(overrides = country_overrides()) {
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

get_world_polygons <- function(region = NULL, overrides = country_overrides()) {
  md <- world_polygons(overrides)
  iso <- resolve_region(region)
  if (is.null(iso)) return(md)
  if (inherits(iso, "wdj_bbox")) {
    bb <- unclass(iso)
    # This drops vertices rather than clipping polygons, so a country straddling
    # the edge keeps a truncated ring that geom_polygon() closes with a straight
    # chord -- France loses 202 of 605 vertices and the ends are 15 degrees
    # apart. The sf backend does a real st_crop(). Say so: the returned tibble
    # gives the caller no way to see it.
    wdj_warn(c(
      "A bounding-box {.arg region} only filters vertices on the polygon backend.",
      "!" = "Countries crossing the edge get an approximate outline.",
      "i" = 'Use {.code geometry = "sf"} for a true clip.'
    ))
    return(dplyr::filter(md, long >= bb[1], lat >= bb[2],
                         long <= bb[3], lat <= bb[4]))
  }
  dplyr::filter(md, .data$iso3c %in% iso)
}

# --- sf backend (rnaturalearth) -----------------------------------------------

build_world_sf <- function(scale = "small", overrides = country_overrides()) {
  need_pkg(c("sf", "rnaturalearth", "rnaturalearthdata"),
           "for the sf geometry backend")
  # The 10m data lives in rnaturalearthhires, which is not on CRAN. Left
  # ungated, rnaturalearth reacts by trying to install it into the user's
  # library from a non-CRAN repo and then fails obscurely; say so instead.
  if (identical(scale, "large") &&
      !has_pkg("rnaturalearthhires")) {
    wdj_abort(c(
      '{.code scale = "large"} (10m) needs the {.pkg rnaturalearthhires} package.',
      "i" = "It is not on CRAN; install it with {.code install.packages(\"rnaturalearthhires\", repos = \"https://ropensci.r-universe.dev\")}.",
      "i" = 'Or use {.code scale = "medium"} (50m), which needs nothing extra.'
    ))
  }
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
                         project = TRUE, overrides = country_overrides()) {
  need_pkg("sf", "for the sf geometry backend")
  # Cache the default-overrides geometry (the common case); a custom override
  # set rebuilds uncached so the caller's overrides actually take effect.
  if (identical(overrides, build_overrides())) {
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
                          crs = sf::st_crs(4326L))
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
  # st_break_antimeridian() toggles the s2 engine and runs an st_intersection
  # internally, so it emits three diagnostic notices ("Spherical geometry (s2)
  # switched off/on" and "although coordinates are longitude/latitude,
  # st_intersection assumes that they are planar"). All three are expected and
  # harmless here, but this is on the path of EVERY sf call, so unsilenced they
  # printed on a plain attach_geometry(geometry = "sf"). quietly_sf() muffles
  # them and redirects the stream, so neither the console nor the caller's
  # message handlers see them.
  ne <- quietly_sf(suppressWarnings(
    tryCatch(sf::st_break_antimeridian(ne, lon_0 = recenter %||% 0),
             error = function(e) ne)
  ))
  # st_break_antimeridian() runs an st_intersection internally, which collapses
  # a single-part MULTIPOLYGON to a POLYGON: Natural Earth hands us 177 uniform
  # MULTIPOLYGONs and this left 148 POLYGON + 29 MULTIPOLYGON, i.e. an
  # sfc_GEOMETRY column. sf::st_coordinates() is not implemented for that, so
  # extracting vertices from world_geometry("countries") -- an ordinary thing to
  # do -- failed. Casting back is a pure type normalisation: a POLYGON becomes a
  # one-part MULTIPOLYGON, the coordinates are untouched.
  ne <- suppressWarnings(sf::st_cast(ne, "MULTIPOLYGON", warn = FALSE))
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
#'   `"small"` (110m), `"medium"` (50m) or `"large"` (10m). `"large"`
#'   additionally needs the `rnaturalearthhires` package, which is not on CRAN
#'   (`install.packages("rnaturalearthhires", repos =`
#'   `"https://ropensci.r-universe.dev")`); `"small"` and `"medium"` need
#'   nothing beyond `rnaturalearthdata`. Coarser scales carry fewer
#'   countries as well as less detail -- see [attach_geometry()].
#' @param region Optional subset: a continent, a group name, a vector of `iso3c`
#'   codes, or a bounding box `c(xmin, ymin, xmax, ymax)`. A box is the one form
#'   that clips the shapes themselves rather than selecting whole countries --
#'   properly, via `sf::st_crop()`, on the `sf` backend. The polygon backend can
#'   only drop the vertices outside the box, which leaves a country straddling
#'   the edge with an approximate outline, so it warns.
#' @param projection Projection for the `sf` backend (see [world_map()]).
#' @param recenter Optional central meridian for a recentred map (e.g. `150`).
#'
#' @return A tibble (polygon backend) or `sf` object (sf backend), with columns
#'   depending on `what`:
#'   \describe{
#'     \item{`"countries"`}{polygon: `long`, `lat`, `group`, `order`, `region`,
#'       `subregion`, `iso3c`, `iso2c`. sf: `iso3c`, `iso2c`, `name_long`.}
#'     \item{`"centroids"`}{the same identifier columns plus `centroid_lon` and
#'       `centroid_lat`.}
#'     \item{`"coastline"`, `"borders"`, `"ocean"`, `"graticule"`}{sf only.}
#'   }
#'   **The centroid columns are in the coordinate system of the object
#'   returned**, so on the sf backend they are projected metres, not degrees --
#'   `centroid_lon` for France is `174097`, not `2.1`. For centroids in degrees
#'   use [country_meta]`$centroid_lon` / `$centroid_lat`, which is also what the
#'   polygon backend returns.
#'
#'   A few Natural Earth features have no ISO code and so come back with `iso3c`
#'   `NA` -- Somaliland at every scale, plus the Indian Ocean Territories and
#'   Ashmore and Cartier Islands from `"medium"` on. They are kept so the land is
#'   still drawn; drop or [country_overrides()] them if you group by `iso3c`.
#'
#'   `"orthographic"` is the one genuinely hemispheric projection: the countries
#'   on the far side have no image and come back as empty geometries (correctly,
#'   but `sf::st_coordinates()` cannot read a column that mixes empty and
#'   non-empty -- drop them first). The other three azimuthal projections
#'   (`"azimuthal_equal_area"`, `"north_polar"`, `"south_polar"`) are Lambert
#'   equal-area and draw the *whole* globe, the far side stretched around the
#'   rim rather than dropped, so pass `region` if you want a polar view of the
#'   northern countries alone.
#'
#'   `"ocean"` is a whole-globe background rectangle. It is unavailable in all
#'   four azimuthal projections -- `"orthographic"` has no image for it, and the
#'   Lambert three cut the globe at the antipode, which collapses the rectangle's
#'   outline -- and it cannot be recentred; both cases error rather than
#'   returning an invisible layer.
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
    # st_union()/st_as_sfc() return a bare sfc, not an sf object. ?world_geometry
    # promises an sf object for this backend, and the other four `what` values
    # deliver one -- so a caller writing code across them found dplyr verbs
    # failing on exactly these two. Wrap them.
    coastline = sf::st_as_sf(sf::st_cast(
      sf::st_union(quietly_sf(suppressWarnings(sf::st_make_valid(countries)))),
      "MULTILINESTRING"
    )),
    borders   = sf::st_cast(countries, "MULTILINESTRING", warn = FALSE),
    graticule = sf::st_transform(
      with_c_numbers(sf::st_graticule()),
      crs = wdj_crs(projection, recenter)
    ),
    ocean = {
      box <- world_outline()
      # A recentred whole-globe background does not survive the round trip: the
      # outline has to be split at the new antimeridian, and the split shape
      # projects to a polygon covering only part of the map -- a blue band
      # across the middle with white edges, which reads as a broken plot. Say
      # so instead of half-drawing it. (st_break_antimeridian() is not used
      # here at all now: with lon_0 = 0 it cuts at +/-180, the outline's own
      # edges, which tore it from Earth's full area down to two thirds of it,
      # and to nothing at all under Mollweide.)
      if ((recenter %||% 0) != 0) {
        wdj_abort(c(
          "{.val ocean} cannot be recentred.",
          "i" = "A whole-globe background has to be split at the new central
                 meridian, and the split shape covers only part of the map.",
          "i" = "Draw it at {.code recenter = NULL}, or use
                 {.code what = \"graticule\"}."
        ))
      }
      out <- sf::st_transform(box, crs = wdj_crs(projection, recenter))
      # The azimuthal projections leave a whole-globe background with no usable
      # image, for two different reasons: "orthographic" shows one hemisphere,
      # and the Lambert three cut the globe at the antipode, which degenerates
      # the rectangle's ring. Detect it by area rather than by projection name,
      # so any future projection with the same problem is covered. Compare
      # against Earth's surface area (about 5.1e14 m^2) rather than zero: the
      # collapse leaves a sliver of a few square metres, not exactly nothing.
      if (!isTRUE(as.numeric(sum(sf::st_area(out))) > 1e12)) {
        wdj_abort(c(
          "{.val ocean} is not available in the {.val {projection}} projection.",
          "i" = "An azimuthal projection either shows one hemisphere or cuts the
                 globe at the antipode, leaving a whole-globe background with no
                 image.",
          "i" = "Use {.code what = \"graticule\"}, or an equal-area world projection."
        ))
      }
      sf::st_as_sf(out)
    }
  )
}

# The whole-globe outline as a lon/lat polygon, walked in 2-degree steps.
#
# st_as_sfc(st_bbox(-180, -90, 180, 90)) looks like the obvious way to build
# this, but under the S2 engine (sf's default since 1.0) it collapses to a
# 2-point, zero-area polygon -- and the collapse is invisible, because
# st_bbox() reports the stored extent rather than recomputing it from the
# coordinates. Constructing the ring explicitly sidesteps that entirely: S2
# never sees a bbox to reinterpret, so no sf_use_s2() juggling is needed here.
# Densifying the edges matters separately -- a 4-corner rectangle has no
# interior points for a curved projection to bend, so it transforms to a shape
# narrower than the map it is meant to sit behind. With both, the transformed
# polygon comes out at Earth's true surface area. st_segmentize() would densify
# it, but on geographic coordinates that needs lwgeom, which is not a
# dependency.
world_outline <- function(step = 2) {
  lons <- seq(-180, 180, by = step)
  lats <- seq(-90, 90, by = step)
  ring <- rbind(
    cbind(lons, -90),          # bottom edge, west to east
    cbind(180, lats),          # right edge, south to north
    cbind(rev(lons), 90),      # top edge, east to west
    cbind(-180, rev(lats))     # left edge, north to south
  )
  sf::st_sfc(sf::st_polygon(list(unname(as.matrix(ring)))),
             crs = sf::st_crs(4326L))
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
#' @param scale Natural Earth resolution for the `sf` backend. `"large"` needs the
#'   non-CRAN `rnaturalearthhires` package; see [world_geometry()]. It also
#'   affects which countries are covered at all -- see below.
#' @param region Optional region subset (see [world_geometry()]).
#' @param projection,recenter Projection, and optional central meridian, for
#'   the `sf` backend (see [world_map()] for the projections available).
#' @param overrides Name -> iso3c overrides applied when matching the geometry
#'   backend's country names (default [country_overrides()]). Pass a custom set
#'   built with [country_overrides()] to add your own.
#'
#' @section One row in, one row out:
#' Geometry is attached once **per row**, not once per country. That is what a
#' panel wants -- one row per country-year, each carrying the shape -- but it
#' means a frame that repeats a country by accident draws that country more than
#' once, and only the last one painted is visible. The package cannot tell the
#' two apart (a panel's time column may be called anything), so reduce to one row
#' per country yourself when that is what you meant.
#'
#' @section Which countries have geometry:
#' The join keeps only countries the chosen backend actually carries, so rows of
#' `data` with no matching geometry are dropped silently -- worth checking first
#' when a country you expected is missing from the map. Coverage differs by
#' backend and, for `"sf"`, by `scale`, which changes *which* countries are
#' present and not merely how detailed they look. Of the 215 countries in
#' [world_snapshot], `"polygon"` carries 210, `"sf"` with `scale = "small"` (the
#' default, 110m) carries 169, and `"sf"` with `scale = "medium"` carries 214:
#' the 110m coastlines omit most small states, so `scale = "medium"` is the fix
#' when microstates matter -- Hong Kong, Macao, Tuvalu and the British Virgin
#' Islands are each in no other backend. Gibraltar alone is in none of them.
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
                            overrides = country_overrides()) {
  geometry <- match.arg(geometry)
  check_string(by, "by")
  if (!by %in% names(data)) {
    wdj_abort("{.arg data} must contain the join column {.val {by}}.")
  }
  # Attaching twice joins a frame that already has one row per vertex back onto
  # the vertex table by country, which is N-squared: the bundled snapshot went
  # from 99,338 rows to 310,977,360. The join declares
  # relationship = "many-to-many" -- correctly, one country really does have many
  # vertices -- so dplyr's own guard against exactly this is switched off.
  if (has_map_geometry(data)) {
    wdj_abort(c(
      "{.arg data} already has map geometry attached.",
      "x" = "Joining it again multiplies the rows (one country's vertices
             against themselves).",
      "i" = "Pass the country-level table, or drop the geometry columns first."
    ))
  }
  data <- tibble::as_tibble(data)

  if (geometry == "polygon") {
    poly <- get_world_polygons(region, overrides = overrides)
    # geometry on the left preserves all polygon rows; values fill in.
    drop <- setdiff(intersect(names(poly), names(data)), by)
    poly <- poly[, setdiff(names(poly), drop), drop = FALSE]
    # relationship: a panel (one row per country-year) against polygon vertices
    # is legitimately many-to-many -- it is what animate_world() and facet_map()
    # are for -- so dplyr's "unexpected many-to-many relationship" warning is
    # noise here. R/cache.R declares it for the same reason.
    out <- dplyr::left_join(poly, data, by = by, na_matches = "never",
                            relationship = "many-to-many")
    return(out)
  }

  geom <- get_world_sf(scale, region, projection, recenter, overrides = overrides)
  drop <- setdiff(intersect(names(geom), names(data)), by)
  geom <- geom[, setdiff(names(geom), drop), drop = FALSE]
  dplyr::left_join(geom, data, by = by, na_matches = "never",
                   relationship = "many-to-many")
}

#' Tag coordinates with the country that contains them
#'
#' Point-in-polygon lookup: given longitude / latitude vectors (or an `sf` POINT
#' object), return the `iso3c` of the country each point falls in -- the bridge
#' for getting point data (events, stations, observations) onto the country
#' spine so it can be joined, aggregated and mapped like everything else.
#'
#' @param lon,lat Equal-length numeric vectors of longitude / latitude, giving
#'   one point per element (ignored if `points` is supplied).
#' @param points Optional `sf` POINT object to use instead of `lon`/`lat`.
#' @param scale Natural Earth resolution for the lookup geometry. `"large"` needs the
#'   non-CRAN `rnaturalearthhires` package; see [world_geometry()].
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
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   locate_country(lon = c(2.35, -74.0), lat = c(48.85, 40.7))  # Paris, NYC
#' }
#' }
locate_country <- function(lon = NULL, lat = NULL, points = NULL,
                           scale = "small", add = "country",
                           tolerance_km = 25) {
  # Unvalidated, this was worse than opaque: `dkm <= tolerance_km` compares as
  # strings when tolerance_km is character, and "2650" <= "a" is TRUE, so a
  # character tolerance snapped EVERY unmatched point to its nearest country --
  # a mid-Pacific point came back as Fiji. Checked before the sf gate, so a bad
  # argument does not report a missing package (as in globe_map()/spin_globe()).
  check_number(tolerance_km, "tolerance_km", lo = 0)
  need_pkg("sf", "for locate_country()")
  geom <- get_world_sf(scale = scale, project = FALSE)        # lon/lat (EPSG:4326)
  if (is.null(points)) {
    if (is.null(lon) || is.null(lat) || length(lon) != length(lat)) {
      wdj_abort("Supply equal-length {.arg lon} and {.arg lat}, or a {.arg points} sf object.")
    }
    points <- sf::st_as_sf(data.frame(lon = lon, lat = lat),
                           coords = c("lon", "lat"), crs = 4326L)
  } else {
    points <- sf::st_transform(points, 4326L)
  }
  # Natural Earth rings can be invalid as spherical geometry, which the strict
  # s2 engine that st_intersects() uses by default on unprojected geometry
  # rejects outright (erroring on the WKB->s2 conversion). Fall back to GEOS's
  # planar predicate -- plenty accurate for point-in-country -- exactly as
  # country_borders() does; quietly_sf() also swallows the s2 toggle's notice.
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
#' curated geometry as the rest of the package. Powers [neighbors()].
#'
#' @section Turning it into a graph:
#' `igraph::graph_from_data_frame()` takes the *first two* columns as the edge
#' endpoints, so pass only the two code columns -- handing it the whole tibble
#' would build edges from each country's code to its own name:
#' ```
#' igraph::graph_from_data_frame(
#'   country_borders()[, c("iso3c_a", "iso3c_b")], directed = FALSE)
#' ```
#' Attaching `igraph` also masks [neighbors()], which it exports too, so call
#' that one as `countryatlas::neighbors()` from then on.
#'
#' @param scale Natural Earth resolution to compute adjacency from. Coarser
#'   scales simplify small slivers and may miss a handful of short borders.
#'   `"large"` needs the non-CRAN `rnaturalearthhires` package; see
#'   [world_geometry()].
#' @param region Optional region subset (see [world_geometry()]); a pair is
#'   only reported when both countries remain in the subset.
#'
#' @return A tibble, one row per bordering pair: `iso3c_a`, `country_a`,
#'   `iso3c_b`, `country_b`. Each unordered pair appears once, with
#'   `iso3c_a <= iso3c_b` alphabetically.
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   head(country_borders(region = "Europe"))
#'   # The whole world is only a little dearer: a fraction of a second.
#'   nrow(country_borders())
#' }
#' }
country_borders <- function(scale = "small", region = NULL) {
  need_pkg("sf", "for country_borders()")
  geom <- get_world_sf(scale = scale, region = region, project = FALSE)
  geom <- geom[!is.na(geom$iso3c), ]
  # A handful of Natural Earth rings are self-intersecting at this
  # resolution; the strict S2 engine st_touches() uses by default on
  # unprojected geometry rejects them outright. GEOS's planar predicate is
  # more forgiving and plenty accurate at country scale. The s2 toggle and
  # st_touches()'s planar-coordinates notice are both noise here, so the calls
  # go through quietly_sf().
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
#' @param scale Natural Earth resolution to compute adjacency from. `"large"` needs the
#'   non-CRAN `rnaturalearthhires` package; see [world_geometry()].
#'
#' @return A tibble with one row per (`iso3c`, `neighbor`) pair: the queried
#'   country's `iso3c`, and each bordering country's `iso3c` and `country`
#'   name (`neighbor`, `neighbor_country`). Countries with no land border
#'   (islands, e.g. Japan, Madagascar) return zero rows.
#'
#' @section Pass a vector, don't loop:
#' Every call rebuilds the whole world's adjacency from polygon topology, so
#' asking about one country costs the same as asking about all of them. `x` is
#' vectorised, and adding countries to a single call only adds the filtering:
#' ```
#' countryatlas::neighbors(c("FRA", "DEU", "ESP"), origin = "iso3c")
#' ```
#' Looping instead pays that rebuild once per country -- for every bordering
#' country in the world, roughly two orders of magnitude more work than one
#' vectorised call. The same applies to [country_borders()], which does the work.
#'
#' @section Name clash with igraph:
#' `igraph` also exports a `neighbors()`, and it takes a graph and a vertex
#' rather than country names. Whichever package is attached later wins, so if
#' you use both -- which [country_borders()] suggests, for building a graph of
#' the adjacency -- qualify this one as `countryatlas::neighbors()`.
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   neighbors("France")
#'   neighbors(c("FRA", "JPN"), origin = "iso3c")   # Japan has no land border
#' }
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
#'   reduced to one row per country first).
#' @param value The value column (unquoted).
#' @param scale Natural Earth resolution for the adjacency (see
#'   [country_borders()]). `"large"` needs the non-CRAN `rnaturalearthhires`
#'   package; see [world_geometry()].
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
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   snap <- countryatlas::world_snapshot$countries
#'   set.seed(42)
#'   morans_i(snap, gdp_per_capita, n_perm = 99)  # GDP clusters in space
#' }
#' }
morans_i <- function(data, value, scale = "small", n_perm = 999) {
  need_pkg("sf", "for morans_i() (adjacency comes from country_borders())")
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, val_name)
  check_numeric_col(data, val_name)
  check_number(n_perm, "n_perm", lo = 0, hi = .Machine$integer.max)
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
  n_perm <- as.integer(n_perm)   # already validated as a count above
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
#' @param a,b Vectors of country names or codes. Either the same length, or one
#'   of them length 1 to compare one country against many.
#' @param origin How to read `a`/`b` (default `"country.name"`).
#'
#' @return A numeric vector of great-circle distances in kilometres (`NA` for
#'   any country that doesn't resolve to a known centroid).
#'
#' @section Countries without a bundled centroid:
#' [country_meta] carries no centroid for a handful of small or dependent
#' territories (Bouvet Island, the British Virgin Islands, Gibraltar, Hong Kong,
#' Macao, Svalbard and Jan Mayen, Tokelau, Tuvalu, the U.S. Minor Outlying
#' Islands and the Aland Islands), and no row at all for Kosovo, because
#' [countrycode::codelist] has none. Those inputs return `NA` here even though
#' the geometry backends do map them -- so [neighbors()] and [country_borders()]
#' know about Kosovo while this function does not.
#' @export
#' @examples
#' distance_between("France", "Germany")
#' distance_between("USA", c("Canada", "Mexico"))
distance_between <- function(a, b, origin = "country.name") {
  # Recycling a length-1 side against n is the useful idiom (one origin, many
  # destinations). Anything else partially recycled and silently paired the
  # wrong countries -- 2 against 3 returned a-b[1], a-b[2] and *a[1]*-b[3],
  # behind only base R's "longer object length" warning.
  if (length(a) != length(b) && length(a) != 1L && length(b) != 1L) {
    wdj_abort(c(
      "{.arg a} and {.arg b} must be the same length, or one of them length 1.",
      "x" = "Got {length(a)} and {length(b)}."
    ))
  }
  iso_a <- wdj_to_iso3c(a, origin = origin)
  iso_b <- wdj_to_iso3c(b, origin = origin)
  meta <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
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
