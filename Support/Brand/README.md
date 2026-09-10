# MenuTune-Logo

`menutune-logo.png` ist das transparente Original und die Quelle für das macOS-App-Icon. Die dunkle Graphit-Kachel, die plastische weiße Audio-Wellenform und der violette Akzent greifen den Stil von DevWatch auf. Der violette Punkt ist ein festes Markenelement. Der Wiedergabestatus in der Menüleiste wird weiterhin separat grün oder gelb angezeigt.

`scripts/build-app.sh` erzeugt daraus Standard- und Retina-Größen von 16 bis 1024 Pixeln und verpackt sie als `MenuTune.icns`. Das Original bleibt unverändert.

Erstellt am 11. September 2026 mit dem integrierten Imagegen-Tool. Stilreferenz: das bestehende DevWatch-Icon aus `Support/Brand/devwatch-logo.png` im DevWatch-Projekt.

## Entwurfsprompt

Use case: logo-brand.
Asset type: production macOS application icon for MenuTune, a minimalist menu-bar music/video player.
Edit the supplied DevWatch app icon into its MenuTune sibling.
Input image role: source icon to edit; preserve its rounded graphite tile silhouette, frontal view, premium softly beveled charcoal material, dimensional white-symbol finish, lighting and transparent outer canvas.
Change the terminal chevron and underscore into ONE bold centered audio-spectrum mark made of five separate thick vertical rounded ivory-white capsule bars. Heights from left to right: short, tall, medium, tall, short. Equal bar widths, generous equal spacing; symmetrical mark, perfectly centered, large and readable at 32px. Keep every bar upright. The five bars together should subtly suggest the rhythm of an M. The highest bars occupy about 45 percent of the tile height.
Replace the green circular indicator with a smaller softly illuminated violet-purple circular inset at the bottom right, using MenuTune's violet accent (#8551EB). It should be a restrained polished lens, not a huge glowing orb. Keep it visually separate from the spectrum; it is a secondary accent.
Remove all terminal glyphs completely. No text, letters, headphones, triangle play symbol, musical notes, extra badges, decorative particles, cables or surrounding scene.
Composition: exactly one square app icon, straight-on with no perspective tilt, same tile shape and roughly the same transparent margin as the input; all four corners visible. Crisp clean geometry with refined 3D depth and subtle shadows. No cast shadow extending far beyond the tile, no fake checkerboard, actual alpha transparency outside the tile. Output a 1024 x 1024 PNG suitable as a master macOS icon.

## Finaler Bearbeitungsprompt

Use case: background-extraction.
Edit only the background of this MenuTune macOS app icon. The current gray-and-white checker pattern is accidentally painted into the image: completely remove that entire patterned background and replace it with genuinely transparent pixels in the PNG alpha channel.
Preserve the icon itself exactly: dark rounded graphite tile, five upright ivory spectrum capsules, purple circular inset, proportions, highlights, shading, straight-on view and position. Do not change the logo design.
All pixels outside the rounded tile silhouette must have alpha zero, with clean antialiased edge pixels. No background color, no checkerboard image, no grid, no fabric. This is a production transparent PNG asset, not a preview of transparency. Square canvas, 1024 by 1024.

