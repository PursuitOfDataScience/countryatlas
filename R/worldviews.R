# Natural Earth worldviews ---------------------------------------------------------
#
# Natural Earth publishes its admin-0 countries under 31 points of view --
# the boundaries as each of those countries' governments draws them -- at
# 1:10m. The package ships no worldview of its own beyond Natural Earth's
# default; the caller chooses one, by the viewing country's ISO code, and the
# provenance records the choice.

# Viewing country -> Natural Earth's file suffix. Natural Earth's own codes are
# ISO's lower-cased except Bangladesh's and Nepal's.
WORLDVIEWS <- c(
  ARG = "arg", BGD = "bdg", BRA = "bra", CHN = "chn", DEU = "deu", EGY = "egy",
  ESP = "esp", FRA = "fra", GBR = "gbr", GRC = "grc", IDN = "idn", IND = "ind",
  ISR = "isr", ITA = "ita", JPN = "jpn", KOR = "kor", MAR = "mar", NPL = "nep",
  NLD = "nld", PAK = "pak", POL = "pol", PRT = "prt", PSE = "pse", RUS = "rus",
  SAU = "sau", SWE = "swe", TUR = "tur", TWN = "twn", UKR = "ukr", USA = "usa",
  VNM = "vnm", ISO = "iso")

check_worldview <- function(worldview, call = rlang::caller_env()) {
  if (is.null(worldview)) return(NULL)
  if (!is.character(worldview) || length(worldview) != 1L || is.na(worldview)) {
    wdj_abort(c("{.arg worldview} must be a single code.",
                "i" = "The viewing country's ISO alpha-3 code, such as
                       {.val IND}, or {.val ISO}."), call = call)
  }
  wv <- ascii_upper(trimws(worldview))
  if (!wv %in% names(WORLDVIEWS)) {
    wdj_abort(c(
      "Natural Earth publishes no worldview for {.val {worldview}}.",
      "i" = "Available: {.val {names(WORLDVIEWS)}}."
    ), class = "countryatlas_unknown_worldview", call = call)
  }
  wv
}

# The worldview's file, downloaded once into the package's cache. Isolated so
# tests can hand back a recorded fixture.
worldview_download <- function(suffix, dest) {
  url <- sprintf(
    "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries_%s.zip",
    suffix)
  curl::curl_download(url, dest, quiet = TRUE,
                      handle = curl::new_handle(timeout = http_timeout()))
  dest
}

# The countries as `worldview` draws them, as sf in longitude/latitude, keyed
# on iso3c the way the sf backend keys Natural Earth.
worldview_countries <- function(worldview, overrides = country_overrides(),
                                call = rlang::caller_env()) {
  need_pkg("sf", "for a worldview's geometry", call = call)
  wv <- check_worldview(worldview, call = call)
  suffix <- WORLDVIEWS[[wv]]
  dir <- file.path(tools::R_user_dir("countryatlas", "cache"), "worldviews",
                   suffix)
  shp <- if (dir.exists(dir)) list.files(dir, "[.]shp$", full.names = TRUE)
  if (!length(shp)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    zip <- tempfile(fileext = ".zip")
    on.exit(unlink(zip), add = TRUE)
    tryCatch(worldview_download(suffix, zip), error = function(e) {
      wdj_abort(c(
        "Could not download Natural Earth's {.val {wv}} worldview.",
        "x" = conditionMessage(e),
        "i" = "It is fetched once, about 5 MB, and kept in
               {.path {dirname(dir)}}."
      ), parent = e, class = "countryatlas_fetch_error", call = call)
    })
    utils::unzip(zip, exdir = dir)
    shp <- list.files(dir, "[.]shp$", full.names = TRUE, recursive = TRUE)
  }
  g <- suppressWarnings(sf::st_read(shp[1], quiet = TRUE))
  iso <- if ("ISO_A3" %in% names(g)) as.character(g$ISO_A3) else rep(NA_character_, nrow(g))
  iso[iso %in% c("-99", "-099", "")] <- NA
  name_col <- intersect(c("ADMIN", "NAME_LONG", "NAME"), names(g))[1]
  need <- is.na(iso) & !is.na(name_col)
  if (any(need)) {
    iso[need] <- suppressWarnings(wdj_to_iso3c(g[[name_col]][need],
                                               custom_match = overrides))
  }
  out <- sf::st_sf(iso3c = iso, name_long = g[[name_col]],
                   geometry = sf::st_geometry(g))
  out <- sf::st_transform(out, 4326)
  out$iso2c <- suppressWarnings(countrycode::countrycode(out$iso3c, "iso3c",
                                                        "iso2c", warn = FALSE))
  attr(out, "countryatlas_worldview") <- wv
  out[, c("iso3c", "iso2c", "name_long")]
}

# The worldview in force: the argument, or the session's dispute_policy().
resolve_worldview <- function(worldview) {
  worldview %||% getOption("countryatlas.worldview")
}
