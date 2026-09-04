# Geometry backends & utilities -------------------------------------------------

# Mean Earth radius (km, IUGG). One definition: ring_area_km2(), haversine_km()
# and tissot_map() all measure ground distance and must agree, and the comment
# on haversine_km() already claimed they shared a constant when in fact each
# carried its own literal.
EARTH_RADIUS_KM <- 6371.0088

# The projections countryatlas knows how to build a CRS for.
wdj_projections <- function() {
  c("equal_earth", "robinson", "mollweide", "natural_earth", "plate_carree",
    "mercator", "winkel_tripel", "eckert4", "gall_peters", "orthographic",
    "azimuthal_equal_area", "north_polar", "south_polar")
}

# Map projection -> a CRS usable by sf::st_transform / ggplot2::coord_sf.
# `recenter` shifts the central meridian (e.g. 150 for a Pacific-centred map);
# `lat0` sets the central latitude for the azimuthal projections (orthographic).
wdj_crs <- function(projection = "equal_earth", recenter = NULL, lat0 = NULL,
                    call = rlang::caller_env()) {
  projection <- check_choice(projection, "projection", wdj_projections(),
                             call = call)
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

# The latitude band a projection can actually draw, or NULL for "all of it".
#
# Mercator's y goes to infinity at the poles, and Natural Earth's Antarctica
# reaches -90. PROJ clamps rather than erroring, so the result was a *finite but
# absurd* extent: the projected bbox ran from y = -106,242,570 to 18,397,474, a
# height 3x the world's width, of which the inhabited world occupied the top
# sixth and the rest was one grey rectangle of smeared Antarctica. Web Mercator
# has clipped at +/-85.05113 (the latitude where the map becomes square) since
# it was defined, for exactly this reason; adopt the same limit so a projection
# the package advertises produces a usable map.
wdj_lat_limits <- function(projection) {
  switch(projection, mercator = c(-85.05113, 85.05113), NULL)
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
  ylim <- wdj_lat_limits(projection)
  if (!is.null(ylim)) {
    # Limits are given in lon/lat and converted by coord_sf(), so the clip is
    # stated where it is meaningful rather than in projected metres.
    return(ggplot2::coord_sf(crs = crs, ylim = ylim,
                             default_crs = sf::st_crs(4326L)))
  }
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
# `scale` picks a Natural Earth resolution, which only the sf backend fetches;
# the polygon backend serves one bundled resolution. Both entry points that
# offer the argument accepted it on the polygon path and ignored it in silence
# -- and never validated it either, so `scale = 2` returned small polygons and
# looked like it had worked. Same shape, and same remedy, as the `recenter`
# notice in get_world_polygons().
warn_recenter_ignored <- function(recenter, where = "the polygon backend") {
  if (is.null(recenter) || isTRUE(all.equal(as.numeric(recenter), 0))) {
    return(invisible(NULL))
  }
  wdj_warn(c(
    "{.arg recenter} is not supported on {where} and is ignored.",
    "!" = "The map is drawn on the default central meridian.",
    "i" = 'Use {.code geometry = "sf"} to recentre.'
  ), class = "countryatlas_recenter_ignored")
  invisible(NULL)
}

# `projection` is documented for the sf backend too, and had no notice of its
# own: the polygon backend returns unprojected long/lat, so asking for
# "mollweide" looked honoured and changed nothing.
warn_projection_ignored <- function(projection,
                                    where = "the polygon backend") {
  if (identical(projection, "equal_earth")) return(invisible(NULL))
  wdj_warn(c(
    "{.arg projection} is not supported on {where} and is ignored.",
    "!" = "The polygons are returned in unprojected longitude/latitude.",
    "i" = 'Use {.code geometry = "sf"} to project.'
  ), class = "countryatlas_projection_ignored")
  invisible(NULL)
}

warn_scale_ignored <- function(scale) {
  if (identical(scale, "small")) return(invisible(NULL))
  wdj_warn(c(
    "{.arg scale} is not supported on the polygon backend and is ignored.",
    "!" = "The bundled polygons are the {.val small} Natural Earth resolution.",
    "i" = 'Use {.code geometry = "sf"} to choose a resolution.'
  ), class = "countryatlas_scale_ignored")
  invisible(NULL)
}

ne_scale <- function(scale = c("small", "medium", "large"),
                     call = rlang::caller_env()) {
  scale <- check_choice(scale, "scale", c("small", "medium", "large"),
                        call = call)
  switch(scale, small = 110L, medium = 50L, large = 10L)
}

# Region presets: continents, common groups and bounding boxes resolve to a set
# of iso3c codes used to subset geometry. Returns NULL for "world".
resolve_region <- function(region, call = rlang::caller_env()) {
  if (is.null(region)) return(NULL)
  # NA reached the nchar()/%in% tests below and came back as base R's bare
  # "missing value where TRUE/FALSE needed".
  if (anyNA(region)) {
    wdj_abort(c(
      "{.arg region} must not contain missing values.",
      "i" = "Use {.code NULL} for the whole world."
    ), call = call)
  }
  # A bounding box: c(xmin, ymin, xmax, ymax).
  if (is.numeric(region) && length(region) == 4L) {
    return(structure(region, class = "wdj_bbox"))
  }
  region <- as.character(region)
  # One trim, before any branch, so they all agree about what the value is.
  # Only the iso3c branch below used to trim, and the disagreement was not
  # merely cosmetic: "FRA " resolved, "Europe " fell through to name matching
  # and errored, and "EU " was *silently* accepted as a three-letter code,
  # because nchar("EU ") is 3 and it is already uppercase, so it reached the
  # "unknown code taken at face value" branch and returned the string "EU ".
  # world_geometry(region = "EU "), and every other public caller of this
  # helper -- world_data(), attach_geometry(), join_world(),
  # country_borders() -- therefore subset to nothing and said nothing --
  # the exact outcome the comment on that branch exists to prevent. A trailing
  # space out of a spreadsheet was all it took.
  #
  # [\h\v] rather than trimws()'s ASCII-only [ \t\r\n] default, for the
  # reason given in wdj_to_iso3c(): a value pasted from a web table or a Word
  # document carries a non-breaking space, which the default class leaves in
  # place. `region` itself is kept untrimmed for the error message, so it
  # still shows exactly what the caller passed.
  reg <- trimws(region, whitespace = "[\\h\\v]")
  continents <- c("Africa", "Americas", "Asia", "Europe", "Oceania")
  if (length(reg) == 1L && reg %in% continents) {
    cl <- countrycode::codelist
    return(cl$iso3c[!is.na(cl$continent) & cl$continent == reg])
  }
  # A named group (EU, OECD, ...).
  groups <- unique(countryatlas::country_groups_tbl$group)
  if (length(reg) == 1L && reg %in% groups) {
    return(country_groups(reg)$iso3c)
  }
  # Otherwise treat as a vector of iso3c codes (or names to be standardised).
  # Codes are recognised case-insensitively: ISO alpha-3 is canonically
  # uppercase, but wdj_to_iso3c(origin = "iso3c") accepts any case, and falling
  # straight through to name matching resolved some lowercase codes ("usa", via
  # countrycode's case-insensitive name regex) while silently dropping others
  # ("can"), so a lowercase vector lost countries without saying so.
  up <- ascii_upper(reg)
  if (all(nchar(up) == 3L) && all(up %in% wdj_known_iso3c())) {
    return(up)
  }
  # An all-uppercase 3-letter vector is still taken at face value even when a
  # code is unknown, so an unrecognised code yields an empty subset rather than
  # being reinterpreted as a country name.
  if (all(nchar(reg) == 3L & ascii_upper(reg) == reg)) {
    return(ascii_upper(reg))
  }
  # Last resort: treat it as country names. If none of them resolves, the
  # subset would be empty and the map would come back blank with nothing said --
  # which is what a typo like "Europ" or "Nowhere" used to produce. (An
  # explicitly-uppercase unknown code is left alone above, deliberately.)
  iso <- wdj_to_iso3c(reg)
  if (!length(iso) || all(is.na(iso))) {
    wdj_abort(c(
      "{.arg region} matched no countries: {.val {region}}.",
      "i" = "Give a continent ({.val {continents}}), a group name (see
             {.fn country_groups}), {.field iso3c} codes, country names, or a
             {.code c(xmin, ymin, xmax, ymax)} bounding box."
    ), call = call)
  }
  iso
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

get_world_polygons <- function(region = NULL, overrides = country_overrides(),
                               recenter = NULL) {
  # The polygon backend cannot recentre: it hands back lon/lat vertices, and
  # shifting them means re-splitting every ring at the new antimeridian, which
  # is what sf::st_break_antimeridian() does on the other backend. `recenter`
  # was simply dropped here, so world_geometry(recenter = 150) and
  # join_world(recenter = 150) returned byte-identical coordinates to
  # recenter = NULL and drew an Atlantic-centred map for someone who asked for
  # a Pacific-centred one. Same shape as the bounding-box warning below: say
  # what the backend cannot do, and name the one that can.
  warn_recenter_ignored(recenter)
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
    # .data$, as everywhere else in the package: a bare `long` falls back to a
    # variable of that name in the calling scope if the column is absent, so it
    # can silently filter on the wrong thing where .data$long errors plainly.
    return(dplyr::filter(md, .data$long >= bb[1], .data$lat >= bb[2],
                         .data$long <= bb[3], .data$lat <= bb[4]))
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
  # Validated here rather than only in ne_scale() below, because the cache key
  # is built from `scale` first: a length-2 value vectorised paste0() into a
  # two-element key, and `[[` on an environment then failed with base R's
  # "wrong arguments for subsetting an environment" -- naming neither the
  # argument nor the package. A typo or a number did reach ne_scale() and error
  # properly; only the multi-value case escaped.
  scale <- check_choice(scale, "scale", c("small", "medium", "large"))
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
#' @param scale Natural Earth resolution for the `sf` backend. The polygon
#'   backend serves one bundled resolution and warns if asked for another:
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
#' @param projection Projection for the `sf` backend (see [world_map()]). The
#'   polygon backend returns unprojected longitude/latitude and warns if asked
#'   to project.
#' @param recenter Optional central meridian (e.g. `150`) for the `sf` backend.
#'   The polygon backend cannot recentre and warns if asked to.
#' @param year Draw the world as it was in this year, via [historical_geometry()]
#'   and CShapes (1886-2019). Returns `sf` keyed on `gwcode`; only
#'   `what = "countries"` is available, and `region` cannot be combined with it.
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
                           recenter = NULL,
                           year = NULL) {
  what <- rlang::arg_match(what)
  geometry <- rlang::arg_match(geometry)
  if (!is.null(year)) {
    # Historical borders come from CShapes, which is an sf-only, countries-only
    # backend keyed on Gleditsch-Ward codes. Route rather than reimplement, and
    # refuse the combinations it cannot serve instead of quietly returning
    # present-day geometry for a historical year.
    if (!identical(what, "countries")) {
      wdj_abort(c(
        '{.code year} is only available for {.val countries}.',
        "i" = 'Got {.val {what}}. Coastlines, graticules and the rest are
               present-day layers.'
      ))
    }
    if (!is.null(region)) {
      wdj_abort(c(
        "{.arg region} and {.arg year} cannot be combined.",
        "i" = "Historical geometry is keyed on Gleditsch-Ward codes, which the
               region presets do not speak. Subset the result yourself."
      ))
    }
    return(historical_geometry(year, projection = projection))
  }

  if (geometry == "polygon") {
    if (!what %in% c("countries", "centroids")) {
      wdj_abort(c(
        "{.val {what}} is only available with {.code geometry = \"sf\"}.",
        "i" = "The polygon backend supports {.val countries} and {.val centroids}."
      ))
    }
    warn_scale_ignored(scale)
    warn_projection_ignored(projection)
    poly <- get_world_polygons(region, recenter = recenter)
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
  R <- EARTH_RADIUS_KM; d2r <- pi / 180
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

# A join that matches *nothing* is not a coverage gap, it is a broken key. The
# basemap genuinely holds fewer countries than the snapshot -- small states have
# no polygon at 110m -- so an unmatched code is ordinary and warning about it
# would be noise. Zero matches is different and unambiguous: lowercase,
# mixed-case and padded iso3c all match nothing, and every country then drew as
# no-data with nothing said. The year= branch already reports its match rate;
# these two did not.
warn_no_geometry_match <- function(keys, geom_keys, by,
                                   call = rlang::caller_env()) {
  k <- unique(as.character(keys))
  k <- k[!is.na(k)]
  if (!length(k) || any(k %in% as.character(geom_keys))) return(invisible(NULL))
  wdj_warn(c(
    "No value of {.field {by}} in {.arg data} matches the geometry.",
    "x" = "Every country will draw as no-data.",
    "i" = "Codes must match exactly. {.fn standardize_country} and
           {.fn join_world} normalise case and surrounding whitespace;
           {.val {utils::head(k, 3)}} did not match."
  ), call = call)
  invisible(NULL)
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
#' @param scale Natural Earth resolution for the `sf` backend. The polygon
#'   backend serves one bundled resolution and warns if asked for another. `"large"` needs the
#'   non-CRAN `rnaturalearthhires` package; see [world_geometry()]. It also
#'   affects which countries are covered at all -- see below.
#' @param region Optional region subset (see [world_geometry()]).
#' @param projection,recenter Projection, and optional central meridian, for
#'   the `sf` backend (see [world_map()] for the projections available). The
#'   polygon backend can do neither and warns if asked.
#' @param overrides Name -> iso3c overrides applied when matching the geometry
#'   backend's country names (default [country_overrides()]). Pass a custom set
#'   built with [country_overrides()] to add your own.
#' @param year Attach historical geometry for this year instead of present-day
#'   borders, via [historical_geometry()]. Entities that never had an ISO code
#'   cannot match on `iso3c`, so a low match rate warns.
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
                            overrides = country_overrides(),
                            year = NULL) {
  geometry <- rlang::arg_match(geometry)
  check_string(by, "by")
  if (!is.null(year)) {
    geom <- historical_geometry(year, projection = projection)
    # CShapes is keyed on gwcode; iso3c is a best-effort extra that is NA for
    # every entity that never had an ISO code. Joining on `by` is still right
    # for the modern-coded ones, and saying how many matched is the honest way
    # to hand back a partial join.
    if (!by %in% names(data)) {
      wdj_abort("{.arg data} must contain the join column {.val {by}}.")
    }
    if (!by %in% names(geom)) {
      wdj_abort(c(
        "Historical geometry has no {.val {by}} column.",
        "i" = "It carries {.field gwcode} and a best-effort {.field iso3c};
               see {.help countryatlas::historical_geometry}."
      ))
    }
    matched <- sum(!is.na(geom[[by]]) & geom[[by]] %in% data[[by]])
    if (matched < nrow(geom) * 0.5) {
      wdj_warn(c(
        "Only {matched} of {nrow(geom)} historical entities matched on {.val {by}}.",
        "i" = "Entities that never had an ISO code cannot match. Join on
               {.field gwcode} for full historical coverage."
      ))
    }
    drop <- setdiff(intersect(names(geom), names(data)), by)
    geom <- geom[, setdiff(names(geom), drop), drop = FALSE]
    return(dplyr::left_join(geom, data, by = by, na_matches = "never",
                            relationship = "many-to-many"))
  }
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
    warn_scale_ignored(scale)
    warn_projection_ignored(projection)
    poly <- get_world_polygons(region, overrides = overrides,
                               recenter = recenter)
    # geometry on the left preserves all polygon rows; values fill in.
    drop <- setdiff(intersect(names(poly), names(data)), by)
    poly <- poly[, setdiff(names(poly), drop), drop = FALSE]
    # relationship: a panel (one row per country-year) against polygon vertices
    # is legitimately many-to-many -- it is what animate_world() and facet_map()
    # are for -- so dplyr's "unexpected many-to-many relationship" warning is
    # noise here. R/cache.R declares it for the same reason.
    warn_no_geometry_match(data[[by]], poly[[by]], by)
    out <- dplyr::left_join(poly, data, by = by, na_matches = "never",
                            relationship = "many-to-many")
    return(out)
  }

  geom <- get_world_sf(scale, region, projection, recenter, overrides = overrides)
  drop <- setdiff(intersect(names(geom), names(data)), by)
  geom <- geom[, setdiff(names(geom), drop), drop = FALSE]
  warn_no_geometry_match(data[[by]], geom[[by]], by)
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
    # Anything that is not sf fell straight into st_transform(), which reports
    # "no applicable method for 'st_transform' applied to an object of class
    # \"data.frame\"" -- an sf internal that names neither the argument nor the
    # fix. A plain lon/lat frame is the commonest thing to pass here, so say
    # what to do with it.
    if (!inherits(points, c("sf", "sfc"))) {
      wdj_abort(c(
        "{.arg points} must be an {.pkg sf} POINT object.",
        "x" = "Got {.cls {class(points)[1]}}.",
        "i" = if (is.data.frame(points))
          'Convert it first with {.code sf::st_as_sf(points, coords = c("lon", "lat"), crs = 4326)},
           or pass the columns as {.arg lon} and {.arg lat}.'
        else 'Pass coordinates as the {.arg lon} and {.arg lat} vectors instead.'
      ))
    }
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
      # st_nearest_points()'s pairing argument is `pairwise`. This asked for
      # `by_element`, which is not a formal of it -- sf absorbs the name into
      # `...` and ignores it -- so instead of length(miss) pairs it returned
      # the full length(miss)^2 cross product, and link[i] then measured some
      # *other* point's distance. Cuba's centroid sits 10.8 km off the 110m
      # coastline and should snap; in a 17-miss call it was measured against
      # American Samoa's point instead, came out at 10167 km, and was dropped
      # to NA. With a single missed point 1x1 is the same thing as pairwise,
      # which is why every one-point example was right and only multi-point
      # calls were wrong -- and why a wrong snap was equally possible, had the
      # bogus distance landed under the tolerance.
      #
      # The length check is the point of the fix as much as the name is: it
      # cannot silently regress to a cross product again.
      link <- sf::st_nearest_points(points[miss, ], geom[near, ],
                                    pairwise = TRUE)
      if (length(link) != length(miss)) {
        link <- do.call(c, lapply(seq_along(miss), function(i) {
          sf::st_nearest_points(points[miss[i], ], geom[near[i], ])
        }))
      }
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
  check_add(add)
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
#' @section Which countries the default leaves out:
#' Adjacency is computed from Natural Earth polygons, and the default
#' `scale = "small"` (110m) has no polygon at all for the European microstates.
#' **Andorra, Liechtenstein, Monaco, San Marino and the Vatican are therefore
#' absent from the table entirely** -- not merely missing a short border, but
#' contributing no rows, despite a land border being the whole of their
#' geography. The default reports 310 pairs over 153 countries; France comes
#' back with 8 neighbours rather than 10.
#'
#' `scale = "medium"` (50m) has all five, giving 322 pairs over 162 countries
#' and France its full list. Use it whenever the microstates matter:
#' ```r
#' country_borders(scale = "medium")
#' ```
#' The same 110m gap is why [morans_i()]'s contiguity weights exclude them --
#' see its `n_excluded` -- and it is the land-border twin of the island problem
#' described in `vignette("honest-maps")`. Note the two Guiana borders are real,
#' not artefacts: French Guiana makes Brazil and Suriname neighbours of France.
#'
#' @param scale Natural Earth resolution to compute adjacency from. This is not
#'   a cosmetic choice -- see *Which countries the default leaves out* below.
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
#' @param warn Whether to report values that do not resolve to a country
#'   (default `TRUE`). They match no border, so without this a typo is
#'   indistinguishable from a country that genuinely has no land neighbour.
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
neighbors <- function(x, origin = "country.name", scale = "small",
                      warn = TRUE) {
  check_bool(warn, "warn")
  iso <- wdj_to_iso3c(x, origin = origin)
  # An unresolved name becomes NA, and the %in% filter below simply never
  # matches it -- so a typo returned no rows, exactly like a country that
  # genuinely has no land border. This function's own example makes that
  # collision explicit ("Japan has no land border"), which is why the two
  # cases have to be told apart. distance_between() takes the same input and
  # has always reported it; this is its message.
  if (isTRUE(warn)) {
    unresolved <- unique(as.character(x)[is.na(iso) & !is.na(x)])
    if (length(unresolved)) {
      wdj_warn(c(
        "{length(unresolved)} value{?s} did not resolve to a country, so
         {?it has/they have} no neighbours here:",
        "*" = "{.val {utils::head(unresolved, 8)}}",
        "i" = "Check {.arg origin}; it is currently {.val {origin}}."
      ))
    }
  }
  borders <- country_borders(scale = scale)
  sym <- dplyr::bind_rows(
    tibble::tibble(iso3c = borders$iso3c_a, neighbor = borders$iso3c_b,
                   neighbor_country = borders$country_b),
    tibble::tibble(iso3c = borders$iso3c_b, neighbor = borders$iso3c_a,
                   neighbor_country = borders$country_a)
  )
  dplyr::filter(sym, .data$iso3c %in% iso)
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
  # Two different reasons for an NA distance, and only one of them is the
  # documented gap. "Resolved to a country, which has no bundled centroid" is
  # expected -- ?distance_between says so, and country_weights() already
  # reports it. "Did not resolve to a country at all" is a mistake, usually the
  # wrong `origin`, and it returned a column of NA with nothing said. Report
  # only that one, so the documented gap stays quiet.
  unresolved <- unique(c(as.character(a)[is.na(iso_a) & !is.na(a)],
                         as.character(b)[is.na(iso_b) & !is.na(b)]))
  if (length(unresolved)) {
    wdj_warn(c(
      "{length(unresolved)} value{?s} did not resolve to a country, so their
       distances are {.val {NA}}:",
      "*" = "{.val {utils::head(unresolved, 8)}}",
      "i" = "Check {.arg origin}; it is currently {.val {origin}}."
    ))
  }
  meta <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
  ca <- meta[match(iso_a, meta$iso3c), ]
  cb <- meta[match(iso_b, meta$iso3c), ]
  haversine_km(ca$centroid_lon, ca$centroid_lat, cb$centroid_lon, cb$centroid_lat)
}

# Haversine great-circle distance (km) between lon/lat points (vectorised,
# recycled the usual R way). Shares the Earth radius constant with
# ring_area_km2() for consistency.
haversine_km <- function(lon1, lat1, lon2, lat2) {
  R <- EARTH_RADIUS_KM
  d2r <- pi / 180
  dlat <- (lat2 - lat1) * d2r
  dlon <- (lon2 - lon1) * d2r
  a <- sin(dlat / 2)^2 + cos(lat1 * d2r) * cos(lat2 * d2r) * sin(dlon / 2)^2
  2 * R * asin(pmin(1, sqrt(a)))
}
