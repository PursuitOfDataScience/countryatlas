# Build the bundled datasets for countryatlas.
# Run from the package root with the package dependencies available:
#   Rscript data-raw/build_datasets.R
# Re-run whenever the curated data or the snapshot year changes.
#
# Geometry-derived fields (centroids, area) are computed from the `maps`
# polygon backend so this script runs on any machine, with or without `sf`.
# The optional low-resolution `sf` snapshot is built only when `sf` and
# `rnaturalearth` are available.

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(countrycode)
})

dir.create("data", showWarnings = FALSE)
SNAPSHOT_YEAR <- 2024L
MEMBERSHIP_AS_OF <- "2026-06-01"  # documented point-in-time for memberships

iso_of <- function(names) {
  countrycode(names, "country.name", "iso3c", warn = FALSE)
}

source("data-raw/overrides_snapshot.R")  # standalone copy of overrides

# --- country_groups_tbl -------------------------------------------------------

groups <- list(
  EU = c("Austria","Belgium","Bulgaria","Croatia","Cyprus","Czechia","Denmark",
         "Estonia","Finland","France","Germany","Greece","Hungary","Ireland",
         "Italy","Latvia","Lithuania","Luxembourg","Malta","Netherlands",
         "Poland","Portugal","Romania","Slovakia","Slovenia","Spain","Sweden"),
  EuroZone = c("Austria","Belgium","Croatia","Cyprus","Estonia","Finland",
               "France","Germany","Greece","Ireland","Italy","Latvia",
               "Lithuania","Luxembourg","Malta","Netherlands","Portugal",
               "Slovakia","Slovenia","Spain"),
  G7 = c("United States","Canada","United Kingdom","France","Germany","Italy",
         "Japan"),
  G20 = c("Argentina","Australia","Brazil","Canada","China","France","Germany",
          "India","Indonesia","Italy","Japan","South Korea","Mexico","Russia",
          "Saudi Arabia","South Africa","Turkey","United Kingdom","United States"),
  # Expanded 1 January 2024 (Egypt, Ethiopia, Iran, the UAE) and again in
  # January 2025 (Indonesia). Saudi Arabia was invited in the same round but has
  # never confirmed accession, so it is deliberately not listed here.
  BRICS = c("Brazil","Russia","India","China","South Africa",
            "Egypt","Ethiopia","Iran","United Arab Emirates","Indonesia"),
  ASEAN = c("Brunei","Cambodia","Indonesia","Laos","Malaysia","Myanmar",
            "Philippines","Singapore","Thailand","Vietnam"),
  EFTA = c("Iceland","Liechtenstein","Norway","Switzerland"),
  # Angola left with effect from 1 January 2024.
  OPEC = c("Algeria","Congo - Brazzaville","Equatorial Guinea","Gabon",
           "Iran","Iraq","Kuwait","Libya","Nigeria","Saudi Arabia",
           "United Arab Emirates","Venezuela"),
  NATO = c("Albania","Belgium","Bulgaria","Canada","Croatia","Czechia",
           "Denmark","Estonia","Finland","France","Germany","Greece","Hungary",
           "Iceland","Italy","Latvia","Lithuania","Luxembourg","Montenegro",
           "Netherlands","North Macedonia","Norway","Poland","Portugal","Romania",
           "Slovakia","Slovenia","Spain","Sweden","Turkey","United Kingdom",
           "United States"),
  OECD = c("Australia","Austria","Belgium","Canada","Chile","Colombia",
           "Costa Rica","Czechia","Denmark","Estonia","Finland","France",
           "Germany","Greece","Hungary","Iceland","Ireland","Israel","Italy",
           "Japan","South Korea","Latvia","Lithuania","Luxembourg","Mexico",
           "Netherlands","New Zealand","Norway","Poland","Portugal","Slovakia",
           "Slovenia","Spain","Sweden","Switzerland","Turkey","United Kingdom",
           "United States"),
  Commonwealth = c("Antigua and Barbuda","Australia","Bahamas","Bangladesh",
    "Barbados","Belize","Botswana","Brunei","Cameroon","Canada","Cyprus",
    "Dominica","Eswatini","Fiji","Gabon","Ghana","Grenada","Guyana","India",
    "Jamaica","Kenya","Kiribati","Lesotho","Malawi","Malaysia","Maldives",
    "Malta","Mauritius","Mozambique","Namibia","Nauru","New Zealand","Nigeria",
    "Pakistan","Papua New Guinea","Rwanda","Saint Kitts and Nevis","Saint Lucia",
    "Saint Vincent and the Grenadines","Samoa","Seychelles","Sierra Leone",
    "Singapore","Solomon Islands","South Africa","Sri Lanka","Tanzania",
    "The Gambia","Togo",
    "Tonga","Trinidad and Tobago","Tuvalu","Uganda","United Kingdom","Vanuatu",
    "Zambia"),
  Mercosur = c("Argentina","Brazil","Paraguay","Uruguay","Bolivia"),
  GCC = c("Bahrain","Kuwait","Oman","Qatar","Saudi Arabia",
          "United Arab Emirates"),
  Nordic = c("Denmark","Finland","Iceland","Norway","Sweden"),
  Visegrad = c("Czechia","Hungary","Poland","Slovakia")
)

country_groups_tbl <- do.call(rbind, lapply(names(groups), function(g) {
  iso <- iso_of(groups[[g]])
  tibble(group = g, iso3c = iso,
         country = countrycode(iso, "iso3c", "country.name.en", warn = FALSE))
}))
country_groups_tbl <- as_tibble(country_groups_tbl) |>
  filter(!is.na(iso3c)) |>
  distinct(group, iso3c, .keep_all = TRUE) |>
  arrange(group, country)
attr(country_groups_tbl, "as_of") <- MEMBERSHIP_AS_OF

# --- common_indicators --------------------------------------------------------

common_indicators <- tribble(
  ~name,                  ~code,              ~description,
  "population",           "SP.POP.TOTL",      "Population, total",
  "gdp",                  "NY.GDP.MKTP.CD",   "GDP (current US$)",
  "gdp_constant",         "NY.GDP.MKTP.KD",   "GDP (constant 2015 US$)",
  "gdp_per_capita",       "NY.GDP.PCAP.KD",   "GDP per capita (constant 2015 US$)",
  "gdp_per_capita_current","NY.GDP.PCAP.CD",  "GDP per capita (current US$)",
  "gni_per_capita",       "NY.GNP.PCAP.CD",   "GNI per capita (current US$)",
  "life_expectancy",      "SP.DYN.LE00.IN",   "Life expectancy at birth (years)",
  "fertility_rate",       "SP.DYN.TFRT.IN",   "Fertility rate (births per woman)",
  "infant_mortality",     "SP.DYN.IMRT.IN",   "Infant mortality rate (per 1,000)",
  "co2_per_capita",       "EN.GHG.CO2.PC.CE.AR5","Carbon dioxide emissions per capita (t)",
  "co2_total",            "EN.GHG.CO2.MT.CE.AR5","Carbon dioxide emissions (Mt)",
  "internet_users",       "IT.NET.USER.ZS",   "Individuals using the Internet (% of pop.)",
  "urban_population",     "SP.URB.TOTL.IN.ZS","Urban population (% of total)",
  "poverty_rate",         "SI.POV.DDAY",      "Poverty headcount ratio at $2.15/day (%)",
  "gini",                 "SI.POV.GINI",      "Gini index",
  "unemployment",         "SL.UEM.TOTL.ZS",   "Unemployment (% of labour force)",
  "school_enrollment",    "SE.PRM.ENRR",      "School enrollment, primary (% gross)",
  "health_expenditure",   "SH.XPD.CHEX.GD.ZS","Current health expenditure (% of GDP)",
  "electricity_access",   "EG.ELC.ACCS.ZS",   "Access to electricity (% of pop.)",
  "mobile_subscriptions", "IT.CEL.SETS.P2",   "Mobile subscriptions (per 100 people)",
  # The two price-conversion series deflate() and to_ppp() fetch by default.
  # They belong in the catalogue for the same reason as the rest: a code the
  # package reaches for should be discoverable without reading the source.
  "gdp_deflator",         "NY.GDP.DEFL.ZS",   "GDP deflator (index, base year varies by country)",
  "ppp_conversion",       "PA.NUS.PPP",       "PPP conversion factor, GDP (LCU per international $)"
)

# --- geometry-derived fields from the maps backend ----------------------------

# Spherical polygon area (km^2) for a single lon/lat ring.
#
# This is a standalone copy of the package's ring_area_km2(), kept here for the
# same reason as overrides_snapshot.R: the script must run without the package
# installed. It has to stay a *copy* and not a fork -- it had silently become
# one. The package's version was fixed for antimeridian wrap (a ring crossing
# 180 came out 179x too large; a polar cap cancelled to ~0) and the fix was
# never brought back here, even though this is the function that computed
# country_meta$area_km2, the centroids, and through the centroids the whole
# world_tiles layout. The check below now makes that drift impossible.
ring_area_km2 <- function(lon, lat) {
  ok <- is.finite(lon) & is.finite(lat)
  lon <- lon[ok]; lat <- lat[ok]
  n <- length(lon)
  if (n < 3) return(0)
  R <- 6371.0088
  d2r <- pi / 180
  lon <- lon * d2r; lat <- lat * d2r
  i <- seq_len(n); j <- c(2:n, 1)
  # Each edge the short way round: differencing modulo 360. See the long
  # comment on the package copy in R/geometry.R for why both failure modes
  # (wrapped ring, polar cap) need it and what the inherent limit is.
  dlon <- lon[j] - lon[i]
  wrapped <- abs(dlon) > pi
  dlon[wrapped] <- dlon[wrapped] - sign(dlon[wrapped]) * 2 * pi
  abs(sum(dlon * (2 + sin(lat[i]) + sin(lat[j]))) * R^2 / 2)
}

# Anchor the formula before using it, rather than trusting that a copy stayed a
# copy. Nothing downstream pinned area_km2 numerically -- the only assertions
# were `> 0` and ">90% non-NA", both of which a 179x-inflated value passes.
local({
  # A 2-degree square at the equator: analytic area 49447 km^2.
  sq <- ring_area_km2(c(0, 2, 2, 0), c(0, 0, 2, 2))
  stopifnot(abs(sq - 49447) < 50)
  # The same square straddling the antimeridian must measure the same. The
  # pre-fix formula gave 8.85e6 here.
  wr <- ring_area_km2(c(179, -179, -179, 179), c(0, 0, 2, 2))
  stopifnot(abs(wr - 49447) < 50)
  # A densified cap at latitude -80: analytic 3.87e6 km^2. The pre-fix formula
  # cancelled this to ~0.
  lons <- seq(-180, 179, by = 1)
  cap <- ring_area_km2(lons, rep(-80, length(lons)))
  stopifnot(abs(cap / 3.87e6 - 1) < 0.01)
  # And agree with the installed package's copy, when there is one.
  if (requireNamespace("countryatlas", quietly = TRUE)) {
    pkg <- get("ring_area_km2", envir = asNamespace("countryatlas"))
    for (ring in list(list(c(0, 2, 2, 0), c(0, 0, 2, 2)),
                      list(c(179, -179, -179, 179), c(0, 0, 2, 2)),
                      list(lons, rep(-80, length(lons))))) {
      stopifnot(isTRUE(all.equal(ring_area_km2(ring[[1]], ring[[2]]),
                                 pkg(ring[[1]], ring[[2]]))))
    }
  }
})

md <- ggplot2::map_data("world")
md$iso3c <- wdj_overrides_iso(md$region)
md <- md[!is.na(md$iso3c), ]

geo <- md |>
  group_by(iso3c, group) |>
  summarise(
    g_area = ring_area_km2(long, lat),
    g_clon = mean(range(long)),
    g_clat = mean(range(lat)),
    .groups = "drop"
  ) |>
  group_by(iso3c) |>
  summarise(
    area_km2 = sum(g_area),
    centroid_lon = g_clon[which.max(g_area)],
    centroid_lat = g_clat[which.max(g_area)],
    .groups = "drop"
  )

# --- country_meta -------------------------------------------------------------

cl <- as_tibble(codelist) |>
  filter(!is.na(iso3c)) |>
  transmute(
    iso3c, iso2c, country = country.name.en, continent,
    region, un_region = un.region.name,
    currency = iso4217c, tld = cctld, flag = unicode.symbol
  )

wdi_meta <- tryCatch({
  as_tibble(WDI::WDI_data$country) |>
    # WDI_data uses "" for an unknown capital, which passed straight through:
    # country_meta ended up with five blank capitals alongside 34 NAs, so
    # is.na(capital) was wrong for five countries and the factsheet printed
    # "capital: " with nothing after it. One encoding for "unknown".
    transmute(iso3c, capital = dplyr::na_if(trimws(capital), ""),
              capital_lat = suppressWarnings(as.numeric(latitude)),
              capital_lon = suppressWarnings(as.numeric(longitude)),
              income)
}, error = function(e) tibble(iso3c = character()))

landlocked_iso <- iso_of(c("Afghanistan","Andorra","Armenia","Austria",
  "Azerbaijan","Belarus","Bhutan","Bolivia","Botswana","Burkina Faso","Burundi",
  "Central African Republic","Chad","Czechia","Eswatini","Ethiopia","Hungary",
  "Kazakhstan","Kyrgyzstan","Laos","Lesotho","Liechtenstein","Luxembourg",
  "Malawi","Mali","Moldova","Mongolia","Nepal","Niger","North Macedonia",
  "Paraguay","Rwanda","San Marino","Serbia","Slovakia","South Sudan",
  "Switzerland","Tajikistan","Turkmenistan","Uganda","Uzbekistan","Vatican City",
  "Zambia","Zimbabwe"))

country_meta <- cl |>
  left_join(wdi_meta, by = "iso3c") |>
  left_join(geo, by = "iso3c") |>
  mutate(landlocked = iso3c %in% landlocked_iso) |>
  as_tibble()

# --- world_tiles: equal-area grid from centroids ------------------------------

build_tiles <- function(meta) {
  d <- meta |>
    filter(!is.na(centroid_lon), !is.na(centroid_lat)) |>
    select(iso3c, country, centroid_lon, centroid_lat)
  if (nrow(d) == 0) {
    return(tibble(iso3c = character(), country = character(),
                  row = integer(), col = integer()))
  }
  ncol <- 40L; nrow_ <- 24L
  d$col0 <- as.integer(cut(d$centroid_lon, breaks = ncol, labels = FALSE))
  d$row0 <- as.integer(cut(-d$centroid_lat, breaks = nrow_, labels = FALSE))
  occupied <- new.env()
  key <- function(r, c) paste0(r, "_", c)
  res_row <- integer(nrow(d)); res_col <- integer(nrow(d))
  ord <- order(abs(d$centroid_lat), decreasing = TRUE)
  for (i in ord) {
    r <- d$row0[i]; c <- d$col0[i]; found <- FALSE
    for (radius in 0:8) {
      for (dr in -radius:radius) {
        for (dc in -radius:radius) {
          rr <- r + dr; cc <- c + dc
          # Clamp to the declared grid on BOTH sides. Only the low side was
          # guarded, so the scan reached col0 + radius: a blocked country at
          # col0 = 40 could be placed at col 41, silently widening the 40x24
          # grid that tile_map() draws and ?world_tiles documents.
          if (rr < 1 || cc < 1 || rr > nrow_ || cc > ncol) next
          k <- key(rr, cc)
          if (is.null(occupied[[k]])) {
            assign(k, TRUE, envir = occupied)
            res_row[i] <- rr; res_col[i] <- cc; found <- TRUE; break
          }
        }
        # `break` leaves only the `dc` loop, so `dr` used to keep going after a
        # cell had already been claimed: the country was then re-placed at the
        # LAST free cell in the square rather than the first, and every cell
        # claimed along the way stayed marked occupied for nobody. That wasted
        # 129 of 368 cells and pushed later countries further out -- mean
        # displacement 1.9 cells and a worst case 7.1 cells from the true
        # position, against 0.9 and 2.8 once the break propagates.
        if (found) break
      }
      if (found) break
    }
    if (!found) {
      # Previously this fell through with res_row/res_col left at 0, emitting a
      # country at (0, 0) -- outside the grid, and colliding with any other
      # country that also failed. 8 rings is 289 candidate cells against 960
      # in the grid, so it cannot happen with today's data; if it ever does,
      # say so rather than shipping a broken row.
      stop("no free tile within radius 8 for ", d$iso3c[i],
           " -- widen the grid or the search radius")
    }
  }
  out <- tibble(iso3c = d$iso3c, country = d$country,
                row = res_row, col = res_col) |>
    arrange(row, col)
  stopifnot(
    !anyDuplicated(out[, c("row", "col")]),
    all(out$row >= 1L & out$row <= nrow_),
    all(out$col >= 1L & out$col <= ncol)
  )
  out
}
world_tiles <- build_tiles(country_meta)

# --- world_snapshot (needs network) -------------------------------------------

snap_indicators <- c(gdp_per_capita = "NY.GDP.PCAP.KD",
                     population = "SP.POP.TOTL",
                     life_expectancy = "SP.DYN.LE00.IN",
                     co2_per_capita = "EN.GHG.CO2.PC.CE.AR5")

fetch_one <- function(nm, code) {
  tryCatch({
    raw <- WDI::WDI(indicator = setNames(code, nm),
                    start = SNAPSHOT_YEAR, end = SNAPSHOT_YEAR, extra = FALSE)
    as_tibble(raw)
  }, error = function(e) {
    message("  indicator ", code, " failed: ", conditionMessage(e)); NULL
  })
}

parts <- Filter(Negate(is.null),
                Map(fetch_one, names(snap_indicators), snap_indicators))
countries_snap <- NULL
if (length(parts)) {
  base <- parts[[1]]
  # relationship = "one-to-one": the runtime equivalent in R/cache.R declares
  # "many-to-many" because two iso2c codes can map to one iso3c, and follows
  # the join with a distinct(). This loop had neither guard, so a repeated
  # iso2c-year pair from the API would have fanned out silently and shipped
  # duplicate country rows -- and every verb would then read the bundled
  # dataset as a malformed panel and start warning about repeated countries.
  # One year per fetch means one row per iso2c, so state that and let the join
  # fail loudly if the API ever says otherwise.
  if (length(parts) > 1) for (j in 2:length(parts)) {
    vc <- setdiff(names(parts[[j]]), c("iso2c","country","year"))
    base <- left_join(base, parts[[j]][, c("iso2c","year",vc)],
                      by = c("iso2c","year"), relationship = "one-to-one")
  }
  base$iso3c <- countrycode(base$iso2c, "iso2c", "iso3c", warn = FALSE)
  valid <- unique(na.omit(codelist$iso3c))
  countries_snap <- base |>
    filter(!is.na(iso3c), iso3c %in% c(valid, "XKX")) |>
    left_join(wdi_meta |> select(iso3c, income), by = "iso3c") |>
    mutate(
      income = factor(income, levels = c("Not classified","Low income",
        "Lower middle income","Upper middle income","High income")),
      continent = countrycode(iso3c, "iso3c", "continent", warn = FALSE),
      region = countrycode(iso3c, "iso3c", "region", warn = FALSE)
    ) |>
    select(iso3c, iso2c, country, continent, region, income,
           any_of(names(snap_indicators))) |>
    arrange(country)
  # The bundled snapshot is a cross-section, and every verb reads it as one.
  # Nothing asserted that: two iso2c codes mapping to one iso3c (the case
  # R/cache.R's distinct() exists for) would have produced two rows for one
  # country, which reads as a duplicated country-year everywhere downstream.
  stopifnot(
    !anyDuplicated(countries_snap$iso3c),
    !anyNA(countries_snap$iso3c),
    nrow(countries_snap) > 150L
  )
}

snap_sf <- NULL
have_sf <- requireNamespace("sf", quietly = TRUE) &&
  requireNamespace("rnaturalearth", quietly = TRUE)
if (have_sf && !is.null(countries_snap)) {
  ne2 <- rnaturalearth::ne_countries(scale = 110, returnclass = "sf")
  iso3c <- ne2$iso_a3; iso3c[iso3c %in% c("-99","-099","")] <- NA
  needs <- is.na(iso3c); iso3c[needs] <- iso_of(ne2$admin[needs])
  ne2$iso3c <- iso3c
  ne2 <- ne2[!is.na(ne2$iso3c), c("iso3c","geometry")]
  snap_sf <- dplyr::left_join(ne2, countries_snap, by = "iso3c")
}

world_snapshot <- list(countries = countries_snap, sf = snap_sf, year = SNAPSHOT_YEAR)

# --- historical_codes ----------------------------------------------------------
# Curated crosswalk of dissolved entities -> successor states (one row per
# entity-successor pair). `iso3c_hist` is the alpha-3 code the entity held at
# dissolution, where one existed (it may since have been inherited by a
# successor, e.g. YEM). Kosovo (XKX) is included among the Yugoslavia /
# Serbia-and-Montenegro successors on a territory basis; filter it out if your
# analysis follows strict UN-membership succession.

# The fourth element is the successor set; the fifth says, per entity, how its
# successors relate to it. That distinction is not decoration: this table
# conflates two relations and audit_time_coverage() read every row as the first.
#
#   "succession"   -- the successors are genuinely new states, created when the
#                     entity dissolved. Data dated before `dissolved` really is
#                     data for a country that did not yet exist.
#   "continuation" -- the same state carried on (possibly with less territory),
#                     or a state that already existed absorbed the entity. The
#                     successor was NOT created at `dissolved`, so a
#                     before-existence test against that year is meaningless.
#
# Sudan is both at once: SDN continued and SSD is new, which is why the relation
# belongs per successor rather than per entity. The continuations are the cases
# `?historical_codes` already warns about -- a code "may since have been
# inherited by a successor (e.g. YEM)".
hist_spec <- list(
  list("Soviet Union",          "SUN", 1991L,
       c("ARM","AZE","BLR","EST","GEO","KAZ","KGZ","LVA","LTU","MDA",
         "RUS","TJK","TKM","UKR","UZB"), "succession"),
  list("Yugoslavia",            "YUG", 1992L,
       c("BIH","HRV","MKD","MNE","SRB","SVN","XKX"), "succession"),
  list("Serbia and Montenegro", "SCG", 2006L, c("SRB","MNE","XKX"), "succession"),
  list("Czechoslovakia",        "CSK", 1993L, c("CZE","SVK"), "succession"),
  # The FRG dates from 1949 and absorbed the GDR; DEU was not created in 1990.
  list("East Germany",          "DDR", 1990L, "DEU", "continuation"),
  list("Netherlands Antilles",  "ANT", 2010L, c("CUW","SXM","BES"), "succession"),
  # The unified republic kept the YEM code, so YEM did not begin in 1990.
  list("North Yemen",           "YEM", 1990L, "YEM", "continuation"),
  list("South Yemen",           "YMD", 1990L, "YEM", "continuation"),
  # SDN continued with less territory; SSD is the new state.
  list("Sudan (former)",        "SDN", 2011L, c("SDN","SSD"),
       c("continuation", "succession")),
  # Egypt and Syria both long predate the UAR and resumed afterwards.
  list("United Arab Republic",  NA_character_, 1961L, c("EGY","SYR"), "continuation"),
  list("Tanganyika",            NA_character_, 1964L, "TZA", "succession"),
  list("Zanzibar",              NA_character_, 1964L, "TZA", "succession"),
  # Unified Vietnam kept the VNM code.
  list("North Vietnam",         "VDR", 1976L, "VNM", "continuation"),
  list("South Vietnam",         "VNM", 1976L, "VNM", "continuation")
)

historical_codes <- dplyr::bind_rows(lapply(hist_spec, function(e) {
  rel <- e[[5]]
  if (length(rel) == 1L) rel <- rep(rel, length(e[[4]]))
  stopifnot(length(rel) == length(e[[4]]),
            all(rel %in% c("succession", "continuation")))
  tibble(historical = e[[1]], iso3c_hist = e[[2]], dissolved = e[[3]],
         iso3c = e[[4]], relation = rel)
}))
# A code listed as one of its own successors is a continuation by construction;
# if that ever disagrees with the declared relation the table is inconsistent.
stopifnot(all(historical_codes$relation[
  !is.na(historical_codes$iso3c_hist) &
    historical_codes$iso3c_hist == historical_codes$iso3c] == "continuation"))
historical_codes$country <- countrycode(historical_codes$iso3c, "iso3c",
                                        "country.name", warn = FALSE)
historical_codes$country[historical_codes$iso3c == "XKX"] <- "Kosovo"
stopifnot(!anyNA(historical_codes$country))

# --- save ---------------------------------------------------------------------

save(historical_codes,   file = "data/historical_codes.rda",   compress = "xz")
save(country_groups_tbl, file = "data/country_groups_tbl.rda", compress = "xz")
save(common_indicators,  file = "data/common_indicators.rda",  compress = "xz")
save(country_meta,       file = "data/country_meta.rda",       compress = "xz")
save(world_tiles,        file = "data/world_tiles.rda",        compress = "xz")
save(world_snapshot,     file = "data/world_snapshot.rda",     compress = "xz")

cat("Datasets written to data/:\n")
cat(" historical_codes:", nrow(historical_codes), "rows\n")
cat(" country_groups_tbl:", nrow(country_groups_tbl), "rows\n")
cat(" common_indicators:", nrow(common_indicators), "rows\n")
cat(" country_meta:", nrow(country_meta), "rows (",
    sum(!is.na(country_meta$centroid_lon)), "with centroids )\n")
cat(" world_tiles:", nrow(world_tiles), "rows\n")
cat(" world_snapshot$countries:", if (is.null(countries_snap)) "NULL" else nrow(countries_snap), "rows\n")
cat(" world_snapshot$sf:", if (is.null(snap_sf)) "NULL" else nrow(snap_sf), "rows\n")
