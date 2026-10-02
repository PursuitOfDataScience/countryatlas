# Record the provider responses the tests replay.
#
# Every adapter test used to mock the client function, so the suite checked the
# parser against the response shape its author assumed and never against the
# live contract -- which is how fetch_owid() and fetch_oecd() could be dead for
# a release without one test failing. These fixtures are real responses,
# trimmed to a handful of countries so the tarball stays small, and the
# scheduled live job (.github/workflows/live-contracts.yaml) re-records them
# and uploads the result for review. Never commit a refresh without reading
# the diff: a changed fixture is a changed provider.
#
# Run from the package root:  Rscript data-raw/record_fixtures.R
# On a machine whose CA bundle is out of date (the IMF's chain needs
# Sectigo's R46 root), point CURL_CA_BUNDLE at a current bundle rather than
# turning verification off.

pkgload::load_all(".", quiet = TRUE)
out_dir <- file.path("tests", "testthat", "fixtures")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
keep <- c("FRA", "DEU", "JPN", "BRA", "NGA", "XKX")
write_body <- function(txt, name) {
  path <- file.path(out_dir, name)
  writeLines(enc2utf8(txt), path, useBytes = TRUE)
  message(sprintf("%-32s %6.1f KB", name, file.size(path) / 1024))
}
get_text <- function(url, accept = NULL) {
  # retry_403: the ILO answers bursts with 403 and serves them a moment later.
  http_text(wdj_http_get(url, accept = accept, retry_403 = TRUE))
}

# --- World Bank, current release: three indicators, 2019-2020 ----------------
# Kept: six countries plus two aggregates (WLD, and AFE, whose code is not a
# country), so the tests see what the filter drops.
wb_keep <- c(keep, "WLD", "AFE")
for (code in c("NY.GDP.PCAP.KD", "SP.POP.TOTL", "SP.DYN.LE00.IN")) {
  url <- sprintf("%s/en/country/all/indicator/%s?format=json&date=2019:2020&per_page=5000&page=1",
                 WB_API, code)
  js <- jsonlite::fromJSON(get_text(url, "application/json"), simplifyVector = FALSE)
  rows <- Filter(function(r) r$countryiso3code %in% wb_keep, js[[2]])
  js[[1]]$total <- length(rows); js[[1]]$pages <- 1L
  write_body(jsonlite::toJSON(list(js[[1]], rows), auto_unbox = TRUE,
                              null = "null", digits = NA),
             sprintf("wb-%s.json", code))
  # What WDI::WDI() returned for the same request, the 3.0.0 path, so the test
  # can show the new client hands back the same keys, columns and values.
  wd <- WDI::WDI(indicator = stats::setNames(code, "value"), start = 2019,
                 end = 2020)
  wd <- wd[wd$iso3c %in% wb_keep, , drop = FALSE]
  saveRDS(wd, file.path(out_dir, sprintf("wdi-%s.rds", code)), version = 2)
}

# --- World Bank archives: one series in one release ---------------------------
url <- sprintf("%s/sources/57/country/all/series/NY.GDP.PCAP.KD/version/202407/time/YR2015;YR2016?format=json&per_page=5000&page=1",
               WB_API)
js <- jsonlite::fromJSON(get_text(url, "application/json"), simplifyVector = FALSE)
iso_of <- function(r) {
  v <- Filter(function(x) identical(x$concept, "Country"), r$variable)
  v[[1]]$id
}
js$source$data <- Filter(function(r) iso_of(r) %in% c(wb_keep, "ADO", "AND"),
                         js$source$data)
js$total <- length(js$source$data); js$pages <- 1L
write_body(jsonlite::toJSON(js, auto_unbox = TRUE, null = "null", digits = NA),
           "wb-archive-202407.json")
# The list of releases, whole: it is the thing wdi_vintages() parses.
write_body(get_text(sprintf("%s/sources/57/version?format=json&per_page=1000",
                            WB_API), "application/json"),
           "wb-vintages.json")

# --- Our World in Data ----------------------------------------------------------
csv <- get_text("https://ourworldindata.org/grapher/life-expectancy.csv?v=1&csvType=full&useColumnShortNames=true",
                "text/csv")
d <- utils::read.csv(text = csv, check.names = FALSE, stringsAsFactors = FALSE,
                     na.strings = "")
d <- d[(d$code %in% c(keep, "OWID_WRL", "OWID_KOS") | is.na(d$code) &
          d$entity == "Africa (UN)") & d$year %in% 2018:2021, , drop = FALSE]
con <- textConnection("owid_csv", "w")
utils::write.csv(d, con, row.names = FALSE, na = "")
close(con)
write_body(paste(owid_csv, collapse = "\n"), "owid-life-expectancy.csv")
write_body(get_text("https://ourworldindata.org/grapher/life-expectancy.metadata.json",
                    "application/json"),
           "owid-life-expectancy.metadata.json")

# --- SDMX: the OECD, the ILO and the IMF ----------------------------------------
write_body(get_text(paste0("https://sdmx.oecd.org/public/rest/data/OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0/",
                           "A.FRA+DEU+JPN.B1GQ_R_GR..?startPeriod=2020&endPeriod=2023&format=csvfilewithlabels")),
           "oecd-naag.csv")
write_body(get_text("https://sdmx.oecd.org/public/rest/dataflow/OECD.SDD.NAD/DSD_NAAG@DF_NAAG_I/1.0?references=datastructure",
                    "application/vnd.sdmx.structure+json;version=1.0"),
           "oecd-naag-structure.json")
write_body(get_text("https://sdmx.ilo.org/rest/data/ILO,DF_UNE_DEAP_SEX_AGE_RT,1.0/FRA+DEU.A..SEX_T.AGE_YTHADULT_YGE15?startPeriod=2020&endPeriod=2022",
                    "application/vnd.sdmx.data+csv;version=1.0.0"),
           "ilo-une.csv")
write_body(get_text("https://sdmx.ilo.org/rest/dataflow/ILO/DF_UNE_DEAP_SEX_AGE_RT/1.0?references=datastructure",
                    "application/vnd.sdmx.structure+json;version=1.0"),
           "ilo-une-structure.json")
write_body(get_text("https://api.imf.org/external/sdmx/2.1/data/IMF.RES,WEO,9.0.0/FRA+DEU.NGDP_RPCH.A?startPeriod=2021&endPeriod=2022",
                    "application/vnd.sdmx.data+csv;version=1.0.0"),
           "imf-weo.csv")
write_body(get_text("https://api.imf.org/external/sdmx/3.0/structure/dataflow/IMF.RES/WEO/9.0.0?references=datastructure",
                    "application/json"),
           "imf-weo-structure.json")
