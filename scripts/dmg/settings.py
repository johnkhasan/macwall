# dmgbuild settings: a classic "drag the app onto Applications" installer window.
# Invoked by scripts/make-dmg.sh with -D app=<path to AeroWall.app> -D background=<tiff>.
import os

application = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
size = None

files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (660, 520))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"

# Must match scripts/dmg/generate_background.py.
icon_size = 112
text_size = 13
icon_locations = {
    app_name: (165, 190),
    "Applications": (495, 190),
}
