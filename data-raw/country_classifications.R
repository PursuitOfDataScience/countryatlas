# Build country_classifications: the World Bank's income and region
# classifications, dated.
#
# world_data() used to take `income` and `region` from the installed WDI
# package's bundled WDI_data, so the classification a user got depended on
# which WDI release happened to be installed -- WDI 2.7.10 disagreed with the
# live World Bank API for eight countries (ETH, FSM, JOR, LKA, PHL, TGO, VEN,
# VNM) and already used the July 2025 region names, while world_snapshot and
# country_meta did not. This table dates every classification, so a panel can
# be classified as of each row's year and a frame can say which vintage it
# carries.
#
# Sources (World Bank, CC BY 4.0):
#   * OGHIST, "World Bank Analytical Classifications", sheet "Country
#     Analytical History": one income group per economy per fiscal year,
#     FY89 onwards. https://ddh-openapi.worldbank.org/resources/DR0095334/download
#   * CLASS, "World Bank Country and Lending Groups", sheet "List of
#     economies": the current region, income group and lending category.
#     https://ddh-openapi.worldbank.org/resources/DR0095333/download
#   * The July 2025 region change: "Since July 1, 2025, Afghanistan and
#     Pakistan are classified as part of the Middle East and North Africa
#     region, moving them from South Asia." World Bank DataBank Metadata
#     Glossary, region TMN,
#     https://databank.worldbank.org/metadataglossary/gender-statistics/country/TMN
#
# Run from the package root:  Rscript data-raw/country_classifications.R

suppressPackageStartupMessages({
  library(tibble)
  library(dplyr)
})

OGHIST_URL <- "https://ddh-openapi.worldbank.org/resources/DR0095334/download"
CLASS_URL <- "https://ddh-openapi.worldbank.org/resources/DR0095333/download"
REGION_CHANGE <- as.Date("2025-07-01")
MENAAP <- "Middle East, North Africa, Afghanistan & Pakistan"
MENA_OLD <- "Middle East & North Africa"

grab <- function(url) {
  f <- tempfile(fileext = ".xlsx")
  utils::download.file(url, f, mode = "wb", quiet = TRUE)
  f
}
oghist <- grab(OGHIST_URL)
class_file <- grab(CLASS_URL)

# --- income: one row per economy per fiscal year -------------------------------

h <- as.data.frame(readxl::read_excel(oghist, sheet = "Country Analytical History",
                                      col_names = FALSE, .name_repair = "minimal"))
fy_row <- which(h[[2]] == "Bank's fiscal year:")
yr_row <- which(h[[2]] == "Data for calendar year :")
stopifnot(length(fy_row) == 1L, length(yr_row) == 1L)
fy_cols <- which(grepl("^FY[0-9]{2}$", unlist(h[fy_row, ])))
fy_lab <- unlist(h[fy_row, fy_cols])
fy <- as.integer(substr(fy_lab, 3, 4))
fy <- ifelse(fy >= 80L, 1900L + fy, 2000L + fy)
gni_year <- as.integer(unlist(h[yr_row, fy_cols]))
# The fiscal-year rule: FY t runs 1 July t-1 to 30 June t and is set from GNI
# per capita for calendar year t-2. Check that the sheet says so for every
# column before relying on it.
stopifnot(identical(gni_year, fy - 2L), !anyDuplicated(fy), !is.unsorted(fy))
# Agreement with the Thresholds sheet: every fiscal year the history covers
# has its four analytical thresholds there, set from the same GNI year.
th <- as.data.frame(readxl::read_excel(oghist, sheet = "Thresholds",
                                       col_names = FALSE, .name_repair = "minimal"))
th_fy_row <- which(th[[1]] == "Bank's fiscal year:")
th_yr_row <- which(th[[1]] == "Data for calendar year :")
th_rows <- match(c("Low income", "Lower middle income", "Upper middle income",
                   "High income"), th[[1]])
stopifnot(length(th_fy_row) == 1L, length(th_yr_row) == 1L, !anyNA(th_rows))
th_cols <- match(fy_lab, unlist(th[th_fy_row, ]))
stopifnot(!anyNA(th_cols),
          identical(as.integer(unlist(th[th_yr_row, th_cols])), gni_year),
          !anyNA(as.matrix(th[th_rows, th_cols])))

rows <- h[!is.na(h[[1]]) & grepl("^[A-Z]{3}f?$", h[[1]]), , drop = FALSE]
# The World Bank's codes for three former entities are not ISO 3166-3's:
# its YUG is Serbia and Montenegro (ISO SCG) and its YUGf is Yugoslavia (ISO
# YUG). The Channel Islands (CHI) have no ISO code at all and are left out.
recode <- c(YUG = "SCG", YUGf = "YUG")
code <- ifelse(rows[[1]] %in% names(recode), recode[rows[[1]]], rows[[1]])
labels <- c(L = "Low income", LM = "Lower middle income",
            UM = "Upper middle income", H = "High income")
income <- bind_rows(lapply(seq_along(fy_cols), function(j) {
  v <- trimws(as.character(rows[[fy_cols[j]]]))
  star <- grepl("\\*$", v)
  v <- sub("\\*$", "", v)
  keep <- v %in% names(labels) & code != "CHI"
  tibble(iso3c = code[keep], scheme = "wb_income", value = unname(labels[v[keep]]),
         from = as.Date(sprintf("%d-07-01", fy[j] - 1L)),
         to = as.Date(sprintf("%d-07-01", fy[j])),
         source = sprintf("World Bank OGHIST, FY%d (GNI per capita %d)",
                          fy[j], gni_year[j]),
         note = ifelse(star[keep],
                       "Yemen, PDR (L) and Yemen, Arab Rep. (LM) were separate; combined they would have been LM.",
                       NA_character_))
}))
# One class per economy per fiscal year.
stopifnot(!anyDuplicated(income[, c("iso3c", "from")]))
latest_fy <- max(fy)

# --- region and lending: the current list, with the July 2025 change dated ----

cl <- as.data.frame(readxl::read_excel(class_file, sheet = "List of economies"))
econ <- cl[!is.na(cl$Region) & cl$Code != "CHI", , drop = FALSE]
# CLASS and OGHIST describe the same fiscal year; refuse a pair that does not.
og_now <- income[income$from == as.Date(sprintf("%d-07-01", latest_fy - 1L)), ]
both <- merge(econ[, c("Code", "Income group")], og_now[, c("iso3c", "value")],
              by.x = "Code", by.y = "iso3c")
stopifnot(nrow(both) > 200L, all(both[["Income group"]] == both$value))

region_rows <- lapply(seq_len(nrow(econ)), function(i) {
  iso <- econ$Code[i]; reg <- econ$Region[i]
  if (identical(reg, MENAAP)) {
    before <- if (iso %in% c("AFG", "PAK")) "South Asia" else MENA_OLD
    tibble(iso3c = iso, scheme = "wb_region", value = c(before, reg),
           from = c(as.Date(NA), REGION_CHANGE), to = c(REGION_CHANGE, as.Date(NA)),
           source = c("World Bank regions before the July 2025 reclassification",
                      "World Bank CLASS, current regions"),
           note = c(if (iso %in% c("AFG", "PAK")) "Moved to MENAAP on 2025-07-01." else
                      "Region renamed on 2025-07-01, when Afghanistan and Pakistan joined it.",
                    NA_character_))
  } else {
    tibble(iso3c = iso, scheme = "wb_region", value = reg, from = as.Date(NA),
           to = as.Date(NA), source = "World Bank CLASS, current regions",
           note = NA_character_)
  }
})
region <- bind_rows(region_rows)
stopifnot(sum(region$value == MENAAP & is.na(region$to)) == 23L,
          all(region$value[region$iso3c %in% c("AFG", "PAK") &
                             region$from %in% REGION_CHANGE] == MENAAP))

lend <- econ[!is.na(econ[["Lending category"]]), , drop = FALSE]
lending <- tibble(
  iso3c = lend$Code, scheme = "wb_lending", value = lend[["Lending category"]],
  from = as.Date(sprintf("%d-07-01", latest_fy - 1L)),
  to = as.Date(sprintf("%d-07-01", latest_fy)),
  source = sprintf("World Bank CLASS, FY%d lending categories", latest_fy),
  note = NA_character_)

country_classifications <- bind_rows(income, region, lending) |>
  arrange(scheme, iso3c, !is.na(from), from)
attr(country_classifications, "vintage") <- sprintf("FY%d", latest_fy)

# --- validation against the live API -------------------------------------------
# The eight countries whose income group WDI 2.7.10 had wrong must resolve to
# the API's current classes.
api <- jsonlite::fromJSON("https://api.worldbank.org/v2/country?format=json&per_page=400")[[2]]
now <- country_classifications[country_classifications$scheme == "wb_income" &
                                 country_classifications$to ==
                                 as.Date(sprintf("%d-07-01", latest_fy)), ]
d8 <- c("ETH", "FSM", "JOR", "LKA", "PHL", "TGO", "VEN", "VNM")
live <- setNames(trimws(api$incomeLevel$value), api$id)
stopifnot(identical(now$value[match(d8, now$iso3c)], unname(live[d8])))

save(country_classifications, file = "data/country_classifications.rda",
     compress = "xz")
cat("country_classifications:", nrow(country_classifications), "rows;",
    "vintage", attr(country_classifications, "vintage"), "\n")
print(table(country_classifications$scheme))
