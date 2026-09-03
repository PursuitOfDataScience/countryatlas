# Keep the test run out of the checking account's file space.
#
# `R CMD check` snapshots `~`, `~/.cache` (recursively) and `/tmp` around the
# run and reports whatever is new as "new files in some other directories" --
# the NOTE CRAN raised against 1.0.0. That one was our own WDI cache, and
# wdj_cache_dir() now sends the cache to the session temp directory whenever
# _R_CHECK_PACKAGE_NAME_ says a check is running.
#
# What is left comes from a package we merely suggest, and 2.0.0 is the first
# version whose tests reach it: rendering a single girafe widget for
# interactive_map(engine = "ggiraph") makes gdtools copy 90 Liberation font
# files into tools::R_user_dir("gdtools", "data"). Those paths are derived from
# environment variables at the moment they are first needed rather than when the
# package loads, so setting them here -- before any test runs -- redirects the
# fonts into the session temp directory, which R deletes on exit. Nothing is
# skipped: the widget still renders, just somewhere disposable.
#
# R_USER_CACHE_DIR *and* XDG_CACHE_HOME are redirected for the same reason even
# though no current test needs it: `~/.cache` is the one tree the check walks
# recursively, so it is where an R-level cache would be most visible. Doing so
# also moves tools::R_user_dir("countryatlas", "cache"), which is harmless --
# test-pre-cran-polish.R compares wdj_cache_dir() against a live R_user_dir()
# call, so it still tells the check branch from the real one.
#
# Both variables, not just XDG_CACHE_HOME: R_user_dir(pkg, "cache") reads
# R_USER_CACHE_DIR *first* and only falls back to XDG_CACHE_HOME, so setting the
# fallback alone left the redirect at the mercy of the machine. Wherever
# R_USER_CACHE_DIR happens to be set the cache escaped to the real user
# directory -- which is how a suggested package's cache reaches `~/.cache/R/`
# and reproduces the "new files in some other directories" NOTE that CRAN
# raised against 1.0.0. comtradr's .onLoad creates ~/.cache/R/comtradr the
# moment its namespace loads, which skip_if_not_installed("comtradr") does.
#
# `~/.cache/R/comtradr` is likewise out of reach, and for a more surprising
# reason: it is not the tests that create it. `R CMD check` resolves every
# `pkg::fun` reference in R/ to confirm the symbol exists, which loads that
# namespace -- and comtradr's .onLoad writes its cache directory. R/sources.R
# calls `comtradr::ct_get_data()`, so the check creates the directory during
# its own static analysis, before any test or example runs. Verified by
# elimination: the directory still appears under
# `--no-tests --no-examples --no-build-vignettes`, while installing the package
# and calling `library(countryatlas)` and `country_sources()` in a fresh HOME
# writes nothing at all. Nothing here can prevent it; any package that calls
# `comtradr::` gets the same NOTE.
#
# One write is deliberately *not* handled here: `~/.cache/fontconfig`. That is
# built by the system fontconfig library the first time R's cairo PNG device
# renders anything, which during a check happens in the separate process that
# re-builds the vignettes -- out of reach of a test setup file, not an R user
# directory, and produced by every package whose vignettes draw a plot.
local({
  dir <- file.path(tempdir(), "countryatlas-user-dirs")
  withr::local_envvar(
    R_USER_DATA_DIR   = file.path(dir, "data"),
    R_USER_CONFIG_DIR = file.path(dir, "config"),
    R_USER_CACHE_DIR  = file.path(dir, "cache"),
    XDG_CACHE_HOME    = file.path(dir, "cache"),
    .local_envir      = testthat::teardown_env()
  )
})
