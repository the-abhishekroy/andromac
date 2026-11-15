# dmgbuild settings: 660x390 window, app on the left, Applications on the right
import os
here = os.path.abspath('dmg')
app = os.path.join(here, '..', 'dist', 'Andromac.app')
format = 'UDZO'
files = [app]
symlinks = {'Applications': '/Applications'}
# no volume icon: one less hidden file to show up for people who have hidden files visible
background = os.path.join(here, 'background.tiff')
window_rect = ((200, 120), (660, 450))   # Finder adds ~60pt of chrome, so the 660x390 background shows in full
icon_size = 104
text_size = 13
icon_locations = {'Andromac.app': (180, 185), 'Applications': (480, 185),
                  # Helper files sit in the empty top corners, INSIDE the window: outside it Finder grows scrollbars, and users with hidden files shown would see them.
                  '.background.tiff': (180, 185), '.VolumeIcon.icns': (480, 185), '.DS_Store': (180, 185), '.fseventsd': (480, 185)}
