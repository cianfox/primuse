# Primuse 2026 app icon system

Nine functional directions use flat geometry across two solid-color families:

- `00-multi-source-playback.png` — default: equalizer columns, playback, and an audio pulse.
- `01-private-library.png` — a personal record archive drawer.
- `02-lossless-audio.png` — a lossless waveform crossing an acoustic diaphragm.
- `03-synchronized-lyrics.png` — highlighted lyrics synchronized to an audio pulse.
- `04-cross-device-continuity.png` — playback handoff between devices.
- `05-headphones-play.png` — headphones surrounding a clear play symbol.
- `06-record-play.png` — a dynamically cropped turntable, record, and tonearm.
- `07-music-note-waveform.png` — an explicit music note, play mark, and waveform.
- `08-speaker-sound.png` — speaker playback with radiating sound.

The `raw/` directory preserves the generated source renders. The files in this directory are the locally normalized 1024×1024 masters used by the asset generator. Local normalization removes generated gradients and shadows by snapping artwork to the exact family palette. The source palette is only used to recognize the shapes; final output colors are applied separately for each appearance.

Light/Any icons use a genuinely light surface with dark, higher-contrast symbols. Dark icons use a deep surface with brighter symbols. Tinted icons use an independent grayscale mapping so the system can apply the user's chosen tint cleanly. `appearance-comparison.png` shows every Light/Dark pair side by side.

## Shared production constraints

Exactly one square master artwork; full-bleed canvas; no baked rounded-square mask, bezel, border, or inset card. Clean flat geometry, 2–4 large shapes, crisp at small sizes. Solid colors only. Primary palette: ink `#102D35`, ivory `#F5F1E8`, coral `#FF6B57`, cyan `#40C3D0`, and yellow `#F4C84C`. Secondary palette: midnight violet `#18142F`, electric violet `#8B6CFF`, mint cyan `#63E6D6`, vivid pink `#FF5F8F`, acid lime `#C9F05A`, and soft white `#F7F5FF`. No text, letters, brand logos, texture, gloss, 3D, glow, watermark, or contact sheet.

## Final generation prompts

### Default — multi-source playback

Create exactly one 1024×1024 master app-icon artwork for Primuse, a personal music-library and multi-source music player. Full-bleed square canvas; do not draw a rounded-square container, border, bezel, inset card, or device mockup. Clean contemporary flat vector geometry, instantly readable at 32 px, large bold rounded shapes, crisp edges, and generous negative space. Use only deep ink teal #102D35, warm ivory #F5F1E8, coral #FF6B57, cyan #40C3D0, and golden yellow #F4C84C as solid fills. On the solid ink background, arrange three giant rounded vertical equalizer columns in cyan, coral, and yellow as one compact rhythmic group with clearly different heights. Cut one oversized warm-ivory right-pointing play triangle through the center of the columns, then join their bases with one broad warm-ivory audio pulse curve. It immediately reads “music playback,” not roads, branching streams, a chart, or an abstract corporate logo. No gradients, gloss, 3D, shadows, glow, grain, texture, tiny equalizer bars, letters, words, music notes, logos, watermark, contact sheet, or multiple options.

### Direction 1 — private library

Use the same primary Primuse canvas, palette, geometry, and exclusions. On the solid ink background, create one warm-ivory archive drawer or record bin spanning the lower third, with three large album sleeves rising from it in a clean asymmetric fan. The central cyan sleeve clearly reveals part of a circular vinyl record; give the record a coral center containing one simple right-pointing play cutout. Use golden yellow only as one large index tab. It immediately reads “my album archive ready to play,” not books, a folder, an app grid, overlapping UI cards, or generic windows. Maximum five major shapes and no tiny sleeve artwork.

### Direction 2 — lossless audio

Use the same primary Primuse canvas, palette, geometry, and exclusions. On the solid ink background, show one large simple warm-ivory speaker diaphragm / acoustic cone made from two bold circular forms, crossed through the center by one clean cyan waveform with only three broad peaks. It immediately reads “high-fidelity lossless audio,” not a target, radar, eye, vinyl record, camera lens, or abstract rings.

### Direction 3 — synchronized lyrics

Use the same primary Primuse canvas, palette, geometry, and exclusions. On the solid ink background, create one dominant warm-ivory speech balloon with a bold asymmetric rounded silhouette. Inside it, place exactly three large lyric blocks in cyan, coral, and warm ivory, with the coral middle block clearly highlighted. Transform the balloon tail seamlessly into one thick cyan waveform sweeping along the bottom edge, and place one golden-yellow timing dot on the waveform directly below the highlighted block. It immediately reads “lyrics moving in time with music,” not a menu, document, chat-app logo, barcode, or generic parallel lines. No actual text, microphone, or vertical playback cursor.

### Direction 4 — cross-device continuity

Use the same primary Primuse canvas, palette, geometry, and exclusions. On the solid ink background, show two simple warm-ivory screen rectangles side by side, connected by one continuous cyan waveform that enters the first screen and exits through the second; add one small coral playback dot moving along the waveform. It immediately reads “music playback handed off between devices,” not a network diagram, chain link, wireless logo, abstract windows, or specific branded hardware.

### Direction 5 — headphones + play

Use case: logo-brand. Asset type: one 1024×1024 Primuse master app icon. Create exactly one full-bleed square artwork with no rounded-square container, bezel, border, inset card, or device mockup. Use only the secondary palette as solid colors. On the midnight-violet background, draw one unmistakable pair of large soft-white over-ear headphones as a bold arch with two simple ear cups, wrapping around one dominant electric-violet right-pointing play triangle. Add one small mint-cyan pulse line beneath it. It instantly reads “music listening and playback,” not a magnet, archway, face, game controller, or abstract symbol. No gradients, lighting, gloss, 3D, shadows, glow, grain, texture, tiny details, letters, words, brand logos, watermark, contact sheet, or multiple options.

### Direction 6 — record + play

Use the same secondary Primuse canvas, palette, geometry, and exclusions. Create a bold top-down turntable composition. Crop one oversized acid-lime vinyl record dynamically into the lower-left corner and use only one broad off-center electric-violet groove arc. Sweep one thick vivid-pink tonearm diagonally from the upper-right toward the record, ending in a mint-cyan stylus touching the groove. Carve one unmistakable soft-white right-pointing play triangle into the record label. It instantly reads “vinyl music playing,” not a centered target, radar, CD-ROM, abstract circles, or an album sleeve. No tiny turntable controls.

### Direction 7 — music note + waveform

Use the same secondary Primuse canvas, palette, geometry, and exclusions. Draw one oversized unmistakable soft-white eighth music note with a thick rounded stem and flag; place a clean electric-violet play-triangle cutout inside its circular note head and add one short mint-cyan waveform accent beside the stem. It instantly reads “music player,” not a letter, speech mark, hook, person, or abstract glyph.

### Direction 8 — speaker + sound

Use the same secondary Primuse canvas, palette, geometry, and exclusions. Draw one large simple soft-white speaker cabinet; inside it, use an acid-lime woofer circle with one vivid-pink play triangle in the center, plus exactly three broad mint-cyan sound-wave arcs radiating to the right. It instantly reads “music playing aloud,” not a camera, washing machine, target, radio antenna, or abstract appliance.

## Regeneration

Run `python3 scripts/generate_app_icon_assets.py` from the repository root after replacing any file under `raw/`. The script normalizes masters, creates iOS light/dark/tinted variants and previews, builds the macOS and watchOS icon sizes, creates tvOS parallax/top-shelf artwork, and refreshes the contact sheet.

tvOS is intentionally not generated from the light iOS master. It keeps a dedicated vivid palette and uses Apple's landscape asset structure: transparent `Front` layers over opaque `Back` layers at 400×240, 800×480, and 1280×768, plus standard and wide Top Shelf artwork. This keeps the parallax stack valid and prevents iOS appearance changes from altering the television artwork.
