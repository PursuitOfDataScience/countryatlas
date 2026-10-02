test_that("country_classifications holds one class per economy per fiscal year", {
  cc <- countryatlas::country_classifications
  expect_identical(names(cc), c("iso3c", "scheme", "value", "from", "to",
                                "source", "note"))
  expect_setequal(unique(cc$scheme), c("wb_income", "wb_region", "wb_lending"))
  inc <- cc[cc$scheme == "wb_income", ]
  expect_false(anyDuplicated(inc[, c("iso3c", "from")]) > 0)
  expect_true(all(inc$value %in% c("Low income", "Lower middle income",
                                   "Upper middle income", "High income")))
  # Fiscal year t runs 1 July t-1 to 30 June t.
  expect_true(all(format(inc$from, "%m-%d") == "07-01"))
  expect_true(all(as.numeric(inc$to - inc$from) %in% c(365, 366)))
  expect_identical(min(inc$from), as.Date("1988-07-01"))   # FY1989
  expect_identical(attr(cc, "vintage"), "FY2027")
  # No spell of any scheme overlaps another for the same country.
  for (sc in unique(cc$scheme)) {
    d <- cc[cc$scheme == sc, ]
    d <- d[order(d$iso3c, d$from, na.last = FALSE), ]
    same <- d$iso3c[-1] == d$iso3c[-nrow(d)]
    prev_to <- d$to[-nrow(d)][same]
    next_from <- d$from[-1][same]
    expect_true(all(!is.na(prev_to) & !is.na(next_from) & prev_to <= next_from),
                info = sc)
  }
})

test_that("twenty country-years match OGHIST cell for cell", {
  # Read straight off the World Bank's OGHIST workbook (sheet "Country
  # Analytical History", by fiscal-year column header) on 2026-10-02, not
  # through the build script. China's FY1999 to FY2000 step down is real.
  L <- "Low income"; LM <- "Lower middle income"; UM <- "Upper middle income"
  H <- "High income"
  spot <- tibble::tribble(
    ~iso3c, ~fy,   ~value,
    "AFG",  1989L, L,  "CHN",  1999L, LM, "CHN",  2000L, L,
    "CHN",  2011L, LM, "IND",  2009L, LM, "IND",  2010L, LM,
    "VNM",  2026L, LM, "VNM",  2027L, UM, "PAK",  2027L, LM,
    "ETH",  2027L, L,  "XKX",  2027L, UM, "USA",  1989L, H,
    "BRA",  2027L, UM, "NGA",  2027L, LM, "ROU",  2020L, UM,
    "ARG",  2018L, UM, "ARG",  2019L, H,  "VEN",  2027L, LM,
    "DZA",  2023L, LM, "DZA",  2024L, LM)
  got <- classify_countries(data.frame(iso3c = spot$iso3c,
                                       year = spot$fy - 1L + 0.5),
                            "income",
                            as_of = as.Date(sprintf("%d-12-31", spot$fy - 1L)))
  expect_identical(as.character(got$income), spot$value)
})

test_that("classify_countries() follows each row's year and the fiscal-year rule", {
  pan <- data.frame(iso3c = c("VNM", "VNM", "PAK", "PAK"),
                    year = c(2026, 2027, 2025, 2026))
  out <- classify_countries(pan, c("income", "region"))
  expect_s3_class(out$income, "factor")
  expect_identical(levels(out$income), countryatlas:::income_levels())
  # 1 January 2026 is in FY2026; 1 January 2027 in FY2027.
  expect_identical(as.character(out$income),
                   c("Lower middle income", "Upper middle income",
                     "Lower middle income", "Lower middle income"))
  # Pakistan moved region on 2025-07-01: 1 January 2025 is before, 2026 after.
  expect_identical(out$region[3:4],
                   c("South Asia", "Middle East, North Africa, Afghanistan & Pakistan"))
  # basis = "data_year": the class computed from 2024 income is FY2026's.
  dy <- classify_countries(data.frame(iso3c = "VNM", year = c(2024, 2025)),
                           "income", basis = "data_year")
  expect_identical(as.character(dy$income),
                   c("Lower middle income", "Upper middle income"))
  # A single as_of for every row; a country not yet classified is NA.
  one <- classify_countries(data.frame(iso3c = c("SSD", "FRA")), "income",
                            as_of = 2005)
  expect_identical(as.character(one$income), c(NA, "High income"))
  expect_identical(source_info(one)$vintage, "FY2005")
})

test_that("classify_countries() validates and handles the edges", {
  skip_slow_on_cran()
  d <- data.frame(iso3c = "FRA", year = 2020)
  expect_error(classify_countries(d, "wealth"), "wealth")
  expect_error(classify_countries(d, character()), "at least one")
  expect_error(classify_countries(data.frame(x = 1)), "iso3c")
  expect_error(classify_countries(d, "income", as_of = "garbage"), "garbage")
  z <- classify_countries(d[0, , drop = FALSE], c("income", "region"))
  expect_identical(nrow(z), 0L)
  expect_s3_class(z$income, "factor")
  expect_warning(classify_countries(data.frame(iso3c = "FRA", income = "x"),
                                    "income"), "income")
})

test_that("world_data() and country_data() classify from the bundled table", {
  # Not from the installed WDI release, which disagreed with the World Bank's
  # own API for eight countries and lagged the July 2025 region change.
  cls <- countryatlas:::country_classification(
    c("ETH", "FSM", "JOR", "LKA", "PHL", "TGO", "VEN", "VNM", "PAK"),
    c("income", "region"))
  now <- classify_countries(data.frame(iso3c = cls$iso3c), c("income", "region"))
  expect_identical(as.character(cls$income), as.character(now$income))
  expect_identical(cls$region[cls$iso3c == "PAK"],
                   "Middle East, North Africa, Afghanistan & Pakistan")
  expect_identical(unique(source_info(cls)$vintage),
                   sprintf("FY%d", countryatlas:::fiscal_year(
                     countryatlas:::classification_now())))
})
