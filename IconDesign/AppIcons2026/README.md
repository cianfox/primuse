# Primuse app icon system

The production catalog contains one primary icon and eight alternates:

- `00-headphones-play.png` — primary icon: headphones, coral play mark, and a short audio pulse.
- `01-private-library.png` — personal record archive.
- `02-lossless-audio.png` — lossless waveform and acoustic diaphragm.
- `03-record-play.png` — cropped turntable and tonearm.
- `04-music-note-waveform.png` — music note, play mark, and waveform.
- `05-speaker-sound.png` — speaker playback.
- `06-soft-note.png` — restored original soft-gradient music note.
- `07-primuse-mark.png` — a white Primuse P with a play-triangle counter.
- `08-muse-spark.png` — a white Muse spark containing a music-note cutout.

The former equalizer default, synchronized-lyrics icon, and cross-device continuity icon are intentionally no longer part of the catalog.

## Appearance system

The primary headphones artwork is quantized from the secondary source palette but uses a dedicated output palette. Violet is not used: Light uses a pale-mint surface, deep-teal headphones, a coral play mark, and a teal pulse; Dark uses a deep-teal surface, warm-ivory headphones, a coral play mark, and a cyan pulse.

The five retained functional alternates continue to use flat geometry and independent Light, Dark, and grayscale Tinted mappings. `06-soft-note` preserves the original historical AppIcon10 Light, Dark, and Tinted PNGs without normalization. The final two icons are generated locally as intentionally minimal brand marks: Primuse plus playback, and Muse plus music.

All iOS masters are 1024×1024 full-bleed RGB PNGs with no baked platform corner mask. macOS sizes are derived from the primary Light icon with the platform-specific inset and rounded mask. watchOS uses the vivid primary headphones palette.

## tvOS

tvOS is generated independently from the primary headphones source. It uses a dark-teal landscape background and a transparent foreground layer containing the warm-ivory headphones, coral play mark, and cyan pulse.

The asset structure remains:

- transparent `Front` plus opaque `Back` at 400×240 and 800×480;
- App Store `Front` plus `Back` at 1280×768;
- Top Shelf at 1920×720 and 3840×1440;
- Top Shelf Wide at 2320×720 and 4640×1440.

## Regeneration

Run `python3 scripts/generate_app_icon_assets.py` from the repository root. The script regenerates all iOS iconsets and previews, the macOS and watchOS primary icons, tvOS parallax and Top Shelf assets, the contact sheet, and the Light/Dark comparison sheet.

The original generated inputs live in `raw/`. `06-soft-note*.png` are the restored historical files. `07-primuse-mark*.png` and `08-muse-spark*.png` are deterministic outputs refreshed by the generator.
