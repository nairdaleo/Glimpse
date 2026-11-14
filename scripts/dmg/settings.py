# dmgbuild settings; values come from make-dmg.sh via -D defines.
import os.path

app = defines["app"]
format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
window_rect = ((200, 120), (660, 420))
icon_size = 112
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
icon_locations = {os.path.basename(app): (180, 190), "Applications": (480, 190)}
