# Hex sticker for countryatlas -> man/figures/logo.png
#
# The sticker is drawn by the package itself — every element is a real
# package capability, not clip art:
#
#   * an orthographic globe built with the package's own projection
#     machinery (`wdj_crs("orthographic")`, the CRS behind `globe_map()`),
#   * carrying a continuous viridis choropleth of log10 GDP per capita from
#     the bundled offline `world_snapshot` (real World Bank data), joined to
#     Natural Earth geometry on the ISO spine by `attach_geometry()`
#     (`world_map()` / `choropleth` vocabulary; viridis is the package's
#     default fill scale, grey-slate = honest "no data"),
#   * amber population spikes rising radially off the horizon from
#     `world_geometry("centroids")` — the `spike_map()` idiom for totals,
#     extruded in true 3-D (tip = surface point scaled by 1 + h, so spikes
#     foreshorten toward the disc centre exactly as a globe would show them),
#   * a five-swatch viridis strip under the wordmark — the binned map legend.
#
# Regenerate from the package root with sf + rnaturalearth(+data) available:
#   Rscript data-raw/hex_logo.R
# Typography: Space Grotesk (https://github.com/floriankarsten/space-grotesk,
# OFL). Falls back to the default sans if not installed.

suppressMessages({
  library(ggplot2)
  library(dplyr)
  library(sf)
})
suppressMessages(pkgload::load_all(".", quiet = TRUE))

# ---- palette -----------------------------------------------------------
col_bg     <- "#0B1B3A"  # deep space navy
col_border <- "#33538F"  # hex rim
col_accent <- "#3AC6A8"  # inner rim accent (viridis teal)
col_ocean  <- "#14295A"
col_grat   <- "#7FB2E5"
col_limb   <- "#A8DCFF"
col_glow   <- "#4FB8FF"
col_spike  <- "#FFC857"
col_na     <- "#2B4066"
col_text   <- "#F2F6FF"

# ---- design parameters -------------------------------------------------
lon0 <- 17; lat0 <- 20     # globe face: Europe/Africa mosaic, S. Asia limb
rg   <- 0.62               # globe radius (hex circumradius = 1)
gy   <- 0.17               # globe centre vertical offset
n_spike <- 15              # spikes: the 15 most populous countries...
r_spike <- 0.50            # ...kept only near the limb (flares, not clutter)

d2r <- pi / 180

# analytic orthographic projection (unit sphere) + hemisphere visibility
ortho_xy <- function(lon, lat) {
  la <- lat * d2r; lo <- lon * d2r; la0 <- lat0 * d2r; lo0 <- lon0 * d2r
  cosc <- sin(la0) * sin(la) + cos(la0) * cos(la) * cos(lo - lo0)
  tibble(
    x = cos(la) * sin(lo - lo0),
    y = cos(la0) * sin(la) - sin(la0) * cos(la) * cos(lo - lo0),
    visible = cosc > 0
  )
}

hexagon <- function(r = 1) {
  a <- (seq(0, 300, by = 60) + 90) * d2r
  tibble(x = r * cos(a), y = r * sin(a))
}

circle <- function(r = 1, cy = gy, n = 300) {
  a <- seq(0, 2 * pi, length.out = n)
  tibble(x = r * cos(a), y = cy + r * sin(a))
}

# ---- the package's own data pipeline -----------------------------------
snap <- countryatlas::world_snapshot$countries
wsf  <- attach_geometry(snap, geometry = "sf")
cent <- world_geometry("centroids", geometry = "polygon")

crs_ortho <- wdj_crs("orthographic", recenter = lon0, lat0 = lat0)

# countries -> orthographic metres -> unit-sphere screen coordinates
wp <- suppressWarnings(st_transform(wsf, crs_ortho))
wp <- wp[!st_is_empty(wp), ]
# per-feature repair: a polygon can degenerate to a point at the horizon
fixed <- lapply(st_geometry(wp), function(g)
  tryCatch(suppressWarnings(st_make_valid(g)), error = function(e) NULL))
keep <- !vapply(fixed, is.null, logical(1))
wp <- st_set_geometry(wp[keep, , drop = FALSE],
                      st_sfc(fixed[keep], crs = crs_ortho))
wp <- suppressWarnings(st_collection_extract(wp, "POLYGON", warn = FALSE))
wp <- suppressWarnings(st_cast(wp, "MULTIPOLYGON"))
wp <- wp[!st_is_empty(wp), ]
wp <- wp[as.numeric(st_area(wp)) > 0, ]

Rm <- 6378137
cc <- st_coordinates(st_geometry(wp))
land <- tibble(
  x = cc[, 1] / Rm, y = cc[, 2] / Rm,
  ring = paste(cc[, "L3"], cc[, "L2"], cc[, "L1"]),
  val  = log10(wp$gdp_per_capita)[cc[, "L3"]]
)

# graticule, computed analytically so it clips cleanly at the horizon
grat <- bind_rows(
  lapply(seq(-150, 180, 30), function(m)
    ortho_xy(m, seq(-84, 84, 1.5)) |> mutate(id = paste0("m", m))),
  lapply(seq(-60, 60, 30), function(p)
    ortho_xy(seq(-180, 180, 1.5), p) |> mutate(id = paste0("p", p)))
) |>
  group_by(id) |>
  mutate(seg = cumsum(!visible)) |>
  filter(visible) |>
  ungroup() |>
  mutate(grp = paste(id, seg))

# spike_map() idiom on the globe: population flares off the limb
sp <- snap |>
  inner_join(cent |> distinct(iso3c, centroid_lon, centroid_lat),
             by = "iso3c") |>
  filter(is.finite(population)) |>
  arrange(desc(population)) |>
  slice_head(n = n_spike)
sp <- bind_cols(sp, ortho_xy(sp$centroid_lon, sp$centroid_lat)) |>
  filter(visible) |>
  mutate(r = sqrt(x^2 + y^2)) |>
  filter(r > r_spike)
h  <- 0.30 * sqrt(sp$population / max(snap$population, na.rm = TRUE))
hw <- 0.011                              # spike half-width at the base
ux <- sp$x / sp$r; uy <- sp$y / sp$r     # radial unit vector
a_sp <- 0.35 + 0.60 * sp$r^2             # fade foreshortened spikes
mk_spikes <- function(w) tibble(
  g = rep(sp$iso3c, each = 3),
  a = rep(a_sp, each = 3),
  x = as.vector(rbind(sp$x - w * hw * uy, sp$x * (1 + h), sp$x + w * hw * uy)),
  y = as.vector(rbind(sp$y + w * hw * ux, sp$y * (1 + h), sp$y - w * hw * ux))
)
spikes      <- mk_spikes(1)
spikes_glow <- mk_spikes(3)

# ---- compose (hex circumradius = 1, pointy-top) -------------------------
sc <- function(df) mutate(df, x = x * rg, y = y * rg + gy)
land <- sc(land); grat <- sc(grat)
spikes <- sc(spikes); spikes_glow <- sc(spikes_glow)

glow <- bind_rows(lapply(1:14, function(i)
  circle(rg * (1 + 0.013 * i)) |> mutate(g = i, a = 0.05 * (1 - i / 15))))
vignette <- bind_rows(lapply(1:6, function(i)
  circle(rg * (1 - 0.006 * i)) |> mutate(g = i)))
swatch <- tibble(x = seq(-2, 2) * 0.088, y = -0.795,
                 f = viridisLite::viridis(5))

wordmark_family <- tryCatch({
  fl <- suppressWarnings(system2("fc-list", stdout = TRUE, stderr = FALSE))
  if (any(grepl("Space Grotesk", fl))) "Space Grotesk" else "sans"
}, error = function(e) "sans")

p <- ggplot() +
  geom_polygon(data = hexagon(), aes(x, y), fill = col_bg) +
  geom_polygon(data = glow, aes(x, y, group = g, alpha = I(a)),
               fill = col_glow) +
  geom_polygon(data = circle(rg), aes(x, y), fill = col_ocean) +
  geom_path(data = grat, aes(x, y, group = grp),
            color = col_grat, linewidth = 0.22, alpha = 0.25) +
  geom_polygon(data = land, aes(x, y, group = ring, subgroup = ring,
                                fill = val),
               color = col_bg, linewidth = 0.12) +
  scale_fill_viridis_c(na.value = col_na, guide = "none") +
  geom_path(data = vignette, aes(x, y, group = g),
            color = "#061128", linewidth = 1.1, alpha = 0.05) +
  geom_path(data = circle(rg), aes(x, y),
            color = col_limb, linewidth = 0.45, alpha = 0.85) +
  geom_polygon(data = spikes_glow, aes(x, y, group = g, alpha = I(a * 0.25)),
               fill = col_spike) +
  geom_polygon(data = spikes, aes(x, y, group = g, alpha = I(a)),
               fill = col_spike, color = col_spike, linewidth = 0.2) +
  annotate("text", x = 0, y = -0.615, label = "countryatlas",
           family = wordmark_family, fontface = 2, size = 8.4,
           color = col_text) +
  geom_tile(data = swatch, aes(x, y), fill = swatch$f,
            width = 0.074, height = 0.042) +
  geom_polygon(data = hexagon(0.945), aes(x, y), fill = NA,
               color = col_accent, linewidth = 0.5, alpha = 0.45) +
  geom_polygon(data = hexagon(), aes(x, y), fill = NA, color = col_border,
               linewidth = 3.2, linejoin = "round") +
  coord_fixed(xlim = c(-0.92, 0.92), ylim = c(-1.04, 1.04), expand = FALSE) +
  theme_void()

ggsave("man/figures/logo.png", p, width = sqrt(3) * 1.9, height = 2 * 1.9,
       dpi = 300, bg = "transparent")
cat("wrote man/figures/logo.png\n")
