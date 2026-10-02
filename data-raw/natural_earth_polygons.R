# Build the polygon backend's geometry: Natural Earth 1:50m admin-0 countries,
# in the vertex form geom_polygon() draws, bundled as internal data.
#
# The polygon backend used to draw maps::map_data("world"), which ?maps::world
# documents as Natural Earth 1:50m imported in 2013. So the default backend
# drew different, older boundaries from the sf backend, the two disagreed on
# which countries exist (210 of the snapshot's countries against 169 and 214),
# and `maps`, a Suggests, was needed to draw the default map at all. This is
# the current Natural Earth release at the same scale, keyed the way the sf
# backend keys it, and needs nothing installed to draw.
#
# Natural Earth is in the public domain: https://www.naturalearthdata.com/about/terms-of-use/
#
# Run from the package root:  Rscript data-raw/natural_earth_polygons.R
# Needs sf at build time only.

suppressPackageStartupMessages(library(sf))
pkgload::load_all(".", quiet = TRUE)

NE_URL <- "https://naciscdn.org/naturalearth/50m/cultural/ne_50m_admin_0_countries.zip"
zip <- tempfile(fileext = ".zip")
utils::download.file(NE_URL, zip, mode = "wb", quiet = TRUE)
dir <- tempfile("ne50")
utils::unzip(zip, exdir = dir)
ne_version <- trimws(readLines(list.files(dir, pattern = "VERSION", full.names = TRUE))[1])
ne <- sf::st_read(list.files(dir, pattern = "[.]shp$", full.names = TRUE),
                  quiet = TRUE)
stopifnot(nrow(ne) >= 240L)

# The ISO code, exactly as the sf backend derives it (build_world_sf()): the
# ISO_A3 column where Natural Earth gives one, and otherwise the country name
# through countrycode and the package's overrides -- which is what recovers
# France, Norway and Kosovo, whose ISO_A3 is -99.
iso <- ne$ISO_A3
iso[iso %in% c("-99", "-099", "")] <- NA
need <- is.na(iso)
iso[need] <- wdj_to_iso3c(ne$ADMIN[need], origin = "country.name",
                          custom_match = country_overrides())
ne$iso3c <- iso

# One group per polygon ring, outer rings only. geom_polygon() fills a ring
# whole, so a hole would be painted over; every hole in admin-0 is another
# country (Lesotho in South Africa, San Marino and the Vatican in Italy), and
# drawing the largest rings first leaves each enclave visible on top of the
# country around it.
rings <- lapply(seq_len(nrow(ne)), function(i) {
  g <- sf::st_geometry(ne)[[i]]
  polys <- if (inherits(g, "MULTIPOLYGON")) unclass(g) else list(unclass(g))
  lapply(polys, function(p) p[[1]])
})
feat <- rep(seq_len(nrow(ne)), lengths(rings))
rings <- unlist(rings, recursive = FALSE)
area <- vapply(rings, function(m) ring_area_km2(m[, 1], m[, 2]), numeric(1))
ord <- order(-area)
ne_polygons <- do.call(rbind, lapply(seq_along(ord), function(k) {
  i <- ord[k]
  m <- rings[[i]]
  m <- m[-nrow(m), , drop = FALSE]          # the ring's closing vertex
  data.frame(long = round(m[, 1], 5), lat = round(m[, 2], 5), group = k,
             order = seq_len(nrow(m)), region = ne$ADMIN[feat[i]],
             iso3c = ne$iso3c[feat[i]], stringsAsFactors = FALSE)
}))
ne_polygons <- tibble::as_tibble(ne_polygons)
attr(ne_polygons, "source") <- sprintf(
  "Natural Earth %s, 1:50m admin-0 countries (public domain)", ne_version)
# Each country's area with its holes taken out (Lesotho out of South Africa),
# which the outer rings drawn above cannot give: country_meta$area_km2 is read
# from here.
feat_area <- vapply(seq_len(nrow(ne)), function(i) {
  g <- sf::st_geometry(ne)[[i]]
  polys <- if (inherits(g, "MULTIPOLYGON")) unclass(g) else list(unclass(g))
  sum(vapply(polys, function(p) {
    a <- vapply(p, function(m) ring_area_km2(m[, 1], m[, 2]), numeric(1))
    a[1] - sum(a[-1])
  }, numeric(1)))
}, numeric(1))
keyed <- !is.na(ne$iso3c)
attr(ne_polygons, "area_km2") <- tapply(feat_area[keyed], ne$iso3c[keyed], sum)

# Territories with their own ISO code that admin-0 draws as part of their
# country -- France's overseas departments, Svalbard, the Caribbean
# Netherlands. Drawn with their country, which is how national statistics
# report them, but country_meta still needs a centroid and an area for each,
# and Natural Earth's map units carry them as units of their own.
MU_URL <- "https://naciscdn.org/naturalearth/50m/cultural/ne_50m_admin_0_map_units.zip"
zip_mu <- tempfile(fileext = ".zip")
utils::download.file(MU_URL, zip_mu, mode = "wb", quiet = TRUE)
dir_mu <- tempfile("ne50mu")
utils::unzip(zip_mu, exdir = dir_mu)
mu <- sf::st_read(list.files(dir_mu, pattern = "[.]shp$", full.names = TRUE),
                  quiet = TRUE)
mu <- mu[!mu$ISO_A3 %in% c("-99", "-099", "") & mu$ISO_A3 != mu$ADM0_A3 &
           !mu$ISO_A3 %in% ne$iso3c, ]
units <- do.call(rbind, lapply(seq_len(nrow(mu)), function(i) {
  g <- sf::st_geometry(mu)[[i]]
  polys <- if (inherits(g, "MULTIPOLYGON")) unclass(g) else list(unclass(g))
  outer <- lapply(polys, function(p) p[[1]])
  a_out <- vapply(outer, function(m) ring_area_km2(m[, 1], m[, 2]), numeric(1))
  big <- outer[[which.max(a_out)]]
  data.frame(
    iso3c = mu$ISO_A3[i], parent = mu$ADM0_A3[i],
    centroid_lon = mean(range(big[, 1])), centroid_lat = mean(range(big[, 2])),
    area_km2 = sum(vapply(polys, function(p) {
      a <- vapply(p, function(m) ring_area_km2(m[, 1], m[, 2]), numeric(1))
      a[1] - sum(a[-1])
    }, numeric(1))))
}))
stopifnot(all(c("GUF", "REU", "SJM", "BES") %in% units$iso3c),
          !anyDuplicated(units$iso3c))
# Each territory's area is its own, so its country's is the rest: ISO's FRA is
# metropolitan France, and country_meta lists French Guiana separately.
area <- attr(ne_polygons, "area_km2")
for (i in seq_len(nrow(units))) {
  if (units$parent[i] %in% names(area)) {
    area[units$parent[i]] <- area[units$parent[i]] - units$area_km2[i]
  }
}
attr(ne_polygons, "area_km2") <- area
attr(ne_polygons, "units") <- tibble::as_tibble(units[, setdiff(names(units), "parent")])
stopifnot(!anyNA(ne_polygons$long), !anyNA(ne_polygons$lat),
          all(abs(ne_polygons$long) <= 180), all(abs(ne_polygons$lat) <= 90))

# Internal data, alongside the other internal tables (country_lifespans).
sys <- new.env()
if (file.exists("R/sysdata.rda")) load("R/sysdata.rda", envir = sys)
assign("ne_polygons", ne_polygons, envir = sys)
save(list = ls(sys), envir = sys, file = "R/sysdata.rda", compress = "xz")
cat(sprintf("ne_polygons: %d vertices, %d rings, %d features, %.0f KB (%s)\n",
            nrow(ne_polygons), max(ne_polygons$group), nrow(ne),
            file.size("R/sysdata.rda") / 1024, ne_version))
