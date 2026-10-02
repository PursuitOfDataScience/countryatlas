test_that("CITATION parses and credits the data sources, not just the package", {
  skip_slow_on_cran()
  path <- system.file("CITATION", package = "countryatlas")
  skip_if(!nzchar(path), "CITATION not installed")
  cit <- utils::readCitationFile(path)
  expect_gt(length(cit), 4L)
  txt <- paste(format(cit, style = "text"), collapse = " ")
  expect_match(txt, "countrycode")
  expect_match(txt, "World Bank")
  expect_match(txt, "Natural Earth")
  expect_match(txt, "Equal Earth")
})

test_that(".Rbuildignore excludes the session-local .claude directory", {
  # It is git-excluded, but R CMD build only reads .Rbuildignore, so without
  # this line the lock file shipped in the tarball ("hidden files" NOTE).
  skip_if_not(file.exists("../../.Rbuildignore"))
  expect_true(any(grepl("claude", readLines("../../.Rbuildignore"))))
})

test_that("every option the package reads is documented on the package page", {
  skip_slow_on_cran()
  # Two of the three were advertised only in NEWS.md -- a changelog, not
  # reference documentation -- so a reader of ?countryatlas had no way to find
  # them. wdj_workers()'s own comment even said "the option is advertised in
  # NEWS", which is how a bad value became reachable in the first place.
  skip_if_no_source_tree()
  src <- unlist(lapply(list.files("../../R", pattern = "[.]R$", full.names = TRUE),
                       readLines, warn = FALSE))
  # Read only from getOption() calls: a bare mention in a comment or a filename
  # like countryatlas.Rmd would otherwise register as an option.
  calls <- unlist(regmatches(
    src, gregexpr('getOption\\("countryatlas\\.[a-z_]+"', src)))
  opts <- unique(sub('^getOption\\("', "", sub('"$', "", calls)))
  expect_gt(length(opts), 0L)
  rd <- paste(readLines("../../man/countryatlas-package.Rd", warn = FALSE),
              collapse = "\n")
  for (o in opts) {
    expect_true(grepl(o, rd, fixed = TRUE),
                info = paste(o, "is read by the package but not documented in",
                             "?countryatlas"))
  }
})

test_that("globalVariables() declares nothing it does not need", {
  skip_slow_on_cran()
  # The list had grown to 29 names; emptying it and reading what R CMD check
  # reported showed only 7 were load-bearing. The rest were covered by the
  # `.data$x` idiom, which needs no declaration. A stale entry silences the "no
  # visible binding" NOTE for a *new* bare use of the same name -- the warning
  # that would otherwise catch a typo -- so keep the list minimal.
  skip_if_no_source_tree()
  files <- list.files("../../R", pattern = "[.]R$", full.names = TRUE)

  # Read the declared names by parsing R, not by regexing text.
  declared <- character(0)
  for (f in files) {
    for (e in parse(f, keep.source = FALSE)) {
      if (is.call(e) &&
          identical(deparse(e[[1]]), "utils::globalVariables")) {
        declared <- c(declared, eval(e[[2]]))
      }
    }
  }
  expect_gt(length(declared), 0L)

  # Every declared name must appear as a bare symbol somewhere -- not as a
  # string, not `$`-subscripted. Walk the parse trees and collect real symbols.
  syms <- character(0)
  collect <- function(x) {
    if (is.name(x)) {
      syms <<- c(syms, as.character(x))
    } else if (is.call(x)) {
      # Skip the RHS of `$` and `@`, which is a name but not a variable use,
      # and skip the globalVariables() call itself.
      if (identical(deparse(x[[1]]), "utils::globalVariables")) return(invisible())
      if (length(x) == 3L && deparse(x[[1]]) %in% c("$", "@")) {
        collect(x[[2]])
        return(invisible())
      }
      for (i in seq_along(x)) {
        if (!is.null(x[[i]])) try(collect(x[[i]]), silent = TRUE)
      }
    }
  }
  for (f in files) for (e in parse(f, keep.source = FALSE)) collect(e)
  syms <- unique(syms)

  expect_identical(setdiff(declared, syms), character(0))
})
