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
# R_USER_CACHE_DIR/XDG_CACHE_HOME is redirected for the same reason even though
# no current test needs it: `~/.cache` is the one tree the check walks
# recursively, so it is where an R-level cache would be most visible. Doing so
# also moves tools::R_user_dir("countryatlas", "cache"), which is harmless --
# test-pre-cran-polish.R compares wdj_cache_dir() against a live R_user_dir()
# call, so it still tells the check branch from the real one.
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
    XDG_CACHE_HOME    = file.path(dir, "cache"),
    .local_envir      = testthat::teardown_env()
  )
})
