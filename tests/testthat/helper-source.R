# Is the package *source tree* two levels up?
#
# `dir.exists("../../R")` is not that test, and using it cost a red CI run: an
# *installed* package also has an `R/` directory -- that is where the lazy-load
# database lives -- so under covr, which runs the tests against an installed
# copy, the guard passed, `list.files(pattern = "[.]R$")` then matched nothing,
# and four tests failed on an empty result instead of skipping. Require actual
# source files, and the sibling directories these tests go on to read.
skip_if_no_source_tree <- function() {
  ok <- length(list.files("../../R", pattern = "[.]R$")) > 0L &&
    dir.exists("../../man")
  testthat::skip_if_not(ok, "package source tree not available")
}
