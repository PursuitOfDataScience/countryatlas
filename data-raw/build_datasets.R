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
  "mobile_subscriptions", "IT.CEL.SETS.P2",   "Mobile subscriptions (per 100 people)"
)

# --- geometry-derived fields from the maps backend ----------------------------

# Spherical polygon area (km^2) for a single lon/lat ring.
ring_area_km2 <- function(lon, lat) {
  R <- 6371.0088
  d2r <- pi / 180
  n <- length(lon)
  if (n < 3) return(0)
  lon <- lon * d2r; lat <- lat * d2r
  i <- seq_len(n); j <- c(2:n, 1)
  total <- sum((lon[j] - lon[i]) * (2 + sin(lat[i]) + sin(lat[j])))
  abs(total * R^2 / 2)
}

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
    transmute(iso3c, capital = capital,
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
      for (dr in -radius:radius) for (dc in -radius:radius) {
        rr <- r + dr; cc <- c + dc
        if (rr < 1 || cc < 1) next
        k <- key(rr, cc)
        if (is.null(occupied[[k]])) {
          assign(k, TRUE, envir = occupied)
          res_row[i] <- rr; res_col[i] <- cc; found <- TRUE; break
        }
      }
      if (found) break
    }
  }
  tibble(iso3c = d$iso3c, country = d$country, row = res_row, col = res_col) |>
    arrange(row, col)
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
  if (length(parts) > 1) for (j in 2:length(parts)) {
    vc <- setdiff(names(parts[[j]]), c("iso2c","country","year"))
    base <- left_join(base, parts[[j]][, c("iso2c","year",vc)], by = c("iso2c","year"))
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

hist_spec <- list(
  list("Soviet Union",          "SUN", 1991L,
       c("ARM","AZE","BLR","EST","GEO","KAZ","KGZ","LVA","LTU","MDA",
         "RUS","TJK","TKM","UKR","UZB")),
  list("Yugoslavia",            "YUG", 1992L,
       c("BIH","HRV","MKD","MNE","SRB","SVN","XKX")),
  list("Serbia and Montenegro", "SCG", 2006L, c("SRB","MNE","XKX")),
  list("Czechoslovakia",        "CSK", 1993L, c("CZE","SVK")),
  list("East Germany",          "DDR", 1990L, "DEU"),
  list("Netherlands Antilles",  "ANT", 2010L, c("CUW","SXM","BES")),
  list("North Yemen",           "YEM", 1990L, "YEM"),
  list("South Yemen",           "YMD", 1990L, "YEM"),
  list("Sudan (former)",        "SDN", 2011L, c("SDN","SSD")),
  list("United Arab Republic",  NA_character_, 1961L, c("EGY","SYR")),
  list("Tanganyika",            NA_character_, 1964L, "TZA"),
  list("Zanzibar",              NA_character_, 1964L, "TZA"),
  list("North Vietnam",         "VDR", 1976L, "VNM"),
  list("South Vietnam",         "VNM", 1976L, "VNM")
)

historical_codes <- dplyr::bind_rows(lapply(hist_spec, function(e) {
  tibble(historical = e[[1]], iso3c_hist = e[[2]], dissolved = e[[3]],
         iso3c = e[[4]])
}))
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
