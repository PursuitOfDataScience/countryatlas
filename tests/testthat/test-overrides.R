test_that("the deprecated wdj_overrides() is gone, and country_overrides() stays", {
  # Soft-deprecated in 2.0.0, warning since 3.0.0, removed in 4.0.0.
  expect_false(exists("wdj_overrides", envir = asNamespace("countryatlas")))
  expect_equal(unname(country_overrides(c(Somaliland = "SOM"))[["Somaliland"]]),
               "SOM")
})
