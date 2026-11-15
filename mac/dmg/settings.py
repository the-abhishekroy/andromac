# dmgbuild settings: 660x390 window, app on the left, Applications on the right
import os
here = os.path.abspath('dmg')
app = os.path.join(here, '..', 'dist', 'Andromac.app')
format = 'UDZO'
files = [app]
symlinks = {'Applications': '/Applications'}
icon = os.path.join(here, '..', 'Resources', 'AppIcon.icns')
background = os.path.join(here, 'background.tiff')
window_rect = ((200, 120), (660, 450))   # Finder adds ~60pt of chrome, so the 660x390 background shows in full
icon_size = 104
text_size = 13
icon_locations = {'Andromac.app': (180, 185), 'Applications': (480, 185),
                  '.background': (1200, 900), '.VolumeIcon.icns': (1200, 900), '.DS_Store': (1200, 900), '.fseventsd': (1200, 900)}   # keep helper files out of sight even if Finder shows hidden files
