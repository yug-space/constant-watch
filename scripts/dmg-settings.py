"""Finder presentation for the signed Constant Watch drag-install image."""
from pathlib import Path
stage = Path(defines['stage'])
application = defines['app']
format = 'ULMO'
filesystem = 'HFS+'
files = [application, str(stage / 'Read me first.txt'), str(stage / 'Third-party notices.txt')]
symlinks = {'Applications': '/Applications'}
hide = ['Read me first.txt', 'Third-party notices.txt']
hide_extension = ['Constant Watch.app']
icon = str(Path(application) / 'Contents/Resources/AppIcon.icns')
background = str(stage / 'installer-background.tiff')
window_rect = ((140, 100), (900, 640))
icon_locations = {'Constant Watch.app': (245, 345), 'Applications': (655, 345)}
icon_size = 128
text_size = 16
label_pos = 'bottom'
arrange_by = None
grid_spacing = 90
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
