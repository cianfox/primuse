#!/usr/bin/env python3
"""Generate every platform asset from the Primuse app-icon masters."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
DESIGN_DIR = ROOT / "IconDesign" / "AppIcons2026"
RAW_DIR = DESIGN_DIR / "raw"
IOS_ASSETS = ROOT / "Primuse" / "Resources" / "Assets.xcassets"
MAC_ICONSET = IOS_ASSETS / "AppIcon-Mac.appiconset"
WATCH_ICONSET = ROOT / "PrimuseWatch" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
TV_BRAND = ROOT / "PrimuseTV" / "Resources" / "Assets.xcassets" / "AppIcon.brandassets"

PRIMARY_SOURCE_PALETTE = [
    (0x10, 0x2D, 0x35),  # ink
    (0xF5, 0xF1, 0xE8),  # ivory
    (0xFF, 0x6B, 0x57),  # coral
    (0x40, 0xC3, 0xD0),  # cyan
    (0xF4, 0xC8, 0x4C),  # yellow
]
PRIMARY_LIGHT_PALETTE = [
    (0xF4, 0xF1, 0xE9),  # warm paper background
    (0x10, 0x2D, 0x35),  # ink symbol
    (0xE9, 0x50, 0x43),  # coral
    (0x0F, 0x91, 0xA0),  # cyan
    (0xD2, 0x98, 0x00),  # yellow
]
PRIMARY_DARK_PALETTE = [
    (0x07, 0x1B, 0x21),
    (0xFA, 0xF7, 0xEF),
    (0xFF, 0x78, 0x66),
    (0x55, 0xD1, 0xDC),
    (0xFF, 0xD5, 0x61),
]
TINTED_PALETTE = [
    (0x18, 0x18, 0x18),
    (0xF2, 0xF2, 0xF2),
    (0xB8, 0xB8, 0xB8),
    (0xD4, 0xD4, 0xD4),
    (0xE2, 0xE2, 0xE2),
    (0xFA, 0xFA, 0xFA),
]

SECONDARY_SOURCE_PALETTE = [
    (0x18, 0x14, 0x2F),  # midnight violet
    (0x8B, 0x6C, 0xFF),  # electric violet
    (0x63, 0xE6, 0xD6),  # mint cyan
    (0xFF, 0x5F, 0x8F),  # vivid pink
    (0xC9, 0xF0, 0x5A),  # acid lime
    (0xF7, 0xF5, 0xFF),  # soft white
]
SECONDARY_LIGHT_PALETTE = [
    (0xF3, 0xF0, 0xFF),  # pale lavender background
    (0x68, 0x47, 0xE6),  # violet
    (0x00, 0x8F, 0x87),  # cyan
    (0xE4, 0x3D, 0x73),  # pink
    (0x86, 0xA9, 0x16),  # lime
    (0x18, 0x14, 0x2F),  # midnight symbol
]
SECONDARY_DARK_PALETTE = [
    (0x0C, 0x09, 0x20),
    (0x9D, 0x83, 0xFF),
    (0x78, 0xF2, 0xE4),
    (0xFF, 0x75, 0x9F),
    (0xD8, 0xF7, 0x72),
    (0xFB, 0xFA, 0xFF),
]

# The primary headphones icon deliberately drops violet entirely. Its source
# artwork still uses the secondary palette, but output maps those indices to a
# calmer mint / deep-teal surface with a coral play mark.
HEADPHONES_LIGHT_PALETTE = [
    (0xE8, 0xFA, 0xF6),  # pale mint background
    (0xE9, 0x50, 0x43),  # coral play mark
    (0x0F, 0x91, 0xA0),  # teal pulse
    (0xE4, 0x3D, 0x73),
    (0xD2, 0x98, 0x00),
    (0x10, 0x2D, 0x35),  # deep-teal headphones
]
HEADPHONES_DARK_PALETTE = [
    (0x07, 0x1B, 0x21),  # deep-teal background
    (0xFF, 0x78, 0x66),  # coral play mark
    (0x55, 0xD1, 0xDC),  # cyan pulse
    (0xFF, 0x75, 0x9F),
    (0xFF, 0xD5, 0x61),
    (0xFA, 0xF7, 0xEF),  # warm-ivory headphones
]

PALETTE_FAMILIES = {
    "primary": (PRIMARY_SOURCE_PALETTE, PRIMARY_LIGHT_PALETTE, PRIMARY_DARK_PALETTE),
    "secondary": (SECONDARY_SOURCE_PALETTE, SECONDARY_LIGHT_PALETTE, SECONDARY_DARK_PALETTE),
    "headphones": (SECONDARY_SOURCE_PALETTE, HEADPHONES_LIGHT_PALETTE, HEADPHONES_DARK_PALETTE),
}

# tvOS artwork is a separate landscape/parallax system. Keep its established
# high-chroma palette independent from the iOS light appearance.
TV_PALETTE = HEADPHONES_DARK_PALETTE

ICONS = [
    ("00-headphones-play.png", "00-headphones-play", "AppIcon", "AppIconPreview", "headphones"),
    ("01-private-library.png", "01-private-library", "AppIcon1", "AppIcon1Preview", "primary"),
    ("02-lossless-audio.png", "02-lossless-audio", "AppIcon2", "AppIcon2Preview", "primary"),
    ("03-record-play.png", "03-record-play", "AppIcon3", "AppIcon3Preview", "secondary"),
    ("04-music-note-waveform.png", "04-music-note-waveform", "AppIcon4", "AppIcon4Preview", "secondary"),
    ("05-speaker-sound.png", "05-speaker-sound", "AppIcon5", "AppIcon5Preview", "secondary"),
]

EXACT_ICONS = [
    (
        "06-soft-note",
        "AppIcon6",
        "AppIcon6Preview",
        "06-soft-note.png",
        "06-soft-note-dark.png",
        "06-soft-note-tinted.png",
    ),
]

SIMPLE_ICONS = [
    ("07-primuse-mark", "AppIcon7", "AppIcon7Preview", "primuse"),
    ("08-muse-spark", "AppIcon8", "AppIcon8Preview", "muse"),
]


def palette_bytes(colors: list[tuple[int, int, int]]) -> list[int]:
    entries = colors + [colors[0]] * (256 - len(colors))
    return [channel for color in entries for channel in color]


def snap_to_palette(source: Path, colors: list[tuple[int, int, int]]) -> Image.Image:
    """Remove generated gradients/shadows while preserving the exact silhouette."""
    image = Image.open(source).convert("RGB")
    palette = Image.new("P", (1, 1))
    palette.putpalette(palette_bytes(colors))
    return image.quantize(palette=palette, dither=Image.Dither.NONE)


def render_variant(indexed: Image.Image, colors: list[tuple[int, int, int]], size: tuple[int, int]) -> Image.Image:
    variant = indexed.copy()
    variant.putpalette(palette_bytes(colors))
    return variant.convert("RGB").resize(size, Image.Resampling.LANCZOS)


def save_ios_assets(
    indexed: Image.Image,
    master_stem: str,
    icon_name: str,
    preview_name: str,
    light_colors: list[tuple[int, int, int]],
    dark_colors: list[tuple[int, int, int]],
) -> tuple[Image.Image, Image.Image]:
    any_icon = render_variant(indexed, light_colors, (1024, 1024))
    dark_icon = render_variant(indexed, dark_colors, (1024, 1024))
    tinted_icon = render_variant(indexed, TINTED_PALETTE, (1024, 1024))

    return save_direct_ios_assets(
        any_icon,
        dark_icon,
        tinted_icon,
        master_stem,
        icon_name,
        preview_name,
    )


def save_direct_ios_assets(
    any_icon: Image.Image,
    dark_icon: Image.Image,
    tinted_icon: Image.Image,
    master_stem: str,
    icon_name: str,
    preview_name: str,
) -> tuple[Image.Image, Image.Image]:
    any_icon = any_icon.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
    dark_icon = dark_icon.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
    tinted_icon = tinted_icon.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)

    master_path = DESIGN_DIR / f"{master_stem}.png"
    any_icon.save(master_path, optimize=True)

    iconset = IOS_ASSETS / f"{icon_name}.appiconset"
    any_icon.save(iconset / f"{icon_name}.png", optimize=True)
    dark_icon.save(iconset / f"{icon_name}-dark.png", optimize=True)
    tinted_icon.save(iconset / f"{icon_name}-tinted.png", optimize=True)

    preview = IOS_ASSETS / f"{preview_name}.imageset"
    any_icon.save(preview / f"{preview_name}.png", optimize=True)
    dark_icon.save(preview / f"{preview_name}-dark.png", optimize=True)
    return any_icon, dark_icon


def diagonal_gradient(start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    size = (1024, 1024)
    vertical = Image.linear_gradient("L").resize(size)
    horizontal = vertical.rotate(90)
    mask = Image.blend(vertical, horizontal, 0.5)
    return Image.composite(Image.new("RGB", size, end), Image.new("RGB", size, start), mask)


def apply_soft_symbol(
    background: Image.Image,
    mask: Image.Image,
    symbol_color: tuple[int, int, int],
) -> Image.Image:
    canvas = background.convert("RGBA")
    blurred = mask.filter(ImageFilter.GaussianBlur(24))
    shifted = blurred.transform(mask.size, Image.Transform.AFFINE, (1, 0, 0, 0, 1, -18))
    shadow_alpha = shifted.point(lambda value: round(value * 0.28))
    shadow = Image.new("RGBA", mask.size, (0x08, 0x2A, 0x32, 0))
    shadow.putalpha(shadow_alpha)
    canvas.alpha_composite(shadow)

    symbol = Image.new("RGBA", mask.size, (*symbol_color, 0))
    symbol.putalpha(mask)
    canvas.alpha_composite(symbol)
    return canvas.convert("RGB")


def make_simple_icon(kind: str, appearance: str) -> Image.Image:
    palettes = {
        "primuse": {
            "light": ((0xE9, 0xFF, 0xF9), (0x38, 0xD5, 0xC8), (0xFF, 0xFD, 0xF6)),
            "dark": ((0x06, 0x2C, 0x35), (0x0F, 0x7F, 0x89), (0xFF, 0xF9, 0xED)),
            "tinted": ((0xF2, 0xF2, 0xF2), (0x6F, 0x6F, 0x6F), (0xFA, 0xFA, 0xFA)),
        },
        "muse": {
            "light": ((0xFF, 0xF5, 0xDF), (0xFF, 0x91, 0x7B), (0xFF, 0xFD, 0xF6)),
            "dark": ((0x31, 0x13, 0x22), (0x9F, 0x37, 0x46), (0xFF, 0xF9, 0xED)),
            "tinted": ((0xF2, 0xF2, 0xF2), (0x75, 0x75, 0x75), (0xFA, 0xFA, 0xFA)),
        },
    }
    start, end, symbol_color = palettes[kind][appearance]
    background = diagonal_gradient(start, end)
    mask = Image.new("L", (1024, 1024), 0)
    draw = ImageDraw.Draw(mask)

    if kind == "primuse":
        # A deliberately simple P monogram. The triangular counter makes the
        # letter simultaneously read as Primuse and playback.
        draw.rounded_rectangle((260, 184, 438, 850), radius=89, fill=255)
        draw.ellipse((340, 184, 824, 662), fill=255)
        draw.polygon(((488, 320), (488, 526), (672, 423)), fill=0)
    elif kind == "muse":
        # The four-point spark represents the "Muse" in Primuse; its large
        # negative-space eighth note anchors the mark explicitly in music.
        draw.polygon(
            (
                (512, 126),
                (612, 402),
                (898, 512),
                (612, 622),
                (512, 898),
                (412, 622),
                (126, 512),
                (412, 402),
            ),
            fill=255,
        )
        draw.ellipse((372, 526, 562, 716), fill=0)
        draw.rounded_rectangle((514, 306, 600, 620), radius=43, fill=0)
        draw.polygon(((556, 306), (734, 386), (706, 480), (586, 423)), fill=0)
    else:
        raise ValueError(f"Unknown simple icon kind: {kind}")

    return apply_soft_symbol(background, mask, symbol_color)


def rounded_mac_master(source: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    body_size = 824
    body = source.resize((body_size, body_size), Image.Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", (body_size, body_size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, body_size - 1, body_size - 1),
        radius=185,
        fill=255,
    )
    body.putalpha(mask)
    canvas.alpha_composite(body, ((1024 - body_size) // 2, (1024 - body_size) // 2))
    return canvas


def save_mac_and_watch(mac_icon: Image.Image, watch_icon: Image.Image) -> None:
    mac_master = rounded_mac_master(mac_icon)
    mac_sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, side in mac_sizes.items():
        mac_master.resize((side, side), Image.Resampling.LANCZOS).save(MAC_ICONSET / filename, optimize=True)
    watch_icon.save(WATCH_ICONSET / "AppIcon.png", optimize=True)


def foreground_layer(indexed: Image.Image, size: tuple[int, int], height_ratio: float = 0.84) -> Image.Image:
    color = render_variant(indexed, TV_PALETTE, indexed.size).convert("RGBA")
    mask = indexed.point([0] + [255] * 255, mode="L")
    color.putalpha(mask)
    target_height = round(size[1] * height_ratio)
    scaled = color.resize((target_height, target_height), Image.Resampling.LANCZOS)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.alpha_composite(scaled, ((size[0] - target_height) // 2, (size[1] - target_height) // 2))
    return layer


def solid_background(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGB", size, TV_PALETTE[0])


def save_tv_assets(default_indexed: Image.Image) -> None:
    targets = [
        (
            TV_BRAND / "App Icon.imagestack" / "Front.imagestacklayer" / "Content.imageset" / "front_400.png",
            TV_BRAND / "App Icon.imagestack" / "Back.imagestacklayer" / "Content.imageset" / "back_400.png",
            (400, 240),
        ),
        (
            TV_BRAND / "App Icon.imagestack" / "Front.imagestacklayer" / "Content.imageset" / "front_800.png",
            TV_BRAND / "App Icon.imagestack" / "Back.imagestacklayer" / "Content.imageset" / "back_800.png",
            (800, 480),
        ),
        (
            TV_BRAND / "App Icon - App Store.imagestack" / "Front.imagestacklayer" / "Content.imageset" / "front_1280.png",
            TV_BRAND / "App Icon - App Store.imagestack" / "Back.imagestacklayer" / "Content.imageset" / "back_1280.png",
            (1280, 768),
        ),
    ]
    for front_path, back_path, size in targets:
        foreground_layer(default_indexed, size).save(front_path, optimize=True)
        solid_background(size).save(back_path, optimize=True)

    shelf_targets = [
        (TV_BRAND / "Top Shelf Image.imageset" / "topshelf.png", (1920, 720)),
        (TV_BRAND / "Top Shelf Image.imageset" / "topshelf@2x.png", (3840, 1440)),
        (TV_BRAND / "Top Shelf Image Wide.imageset" / "topshelf_wide.png", (2320, 720)),
        (TV_BRAND / "Top Shelf Image Wide.imageset" / "topshelf_wide@2x.png", (4640, 1440)),
    ]
    for path, size in shelf_targets:
        shelf = solid_background(size).convert("RGBA")
        shelf.alpha_composite(foreground_layer(default_indexed, size, height_ratio=0.72))
        shelf.convert("RGB").save(path, optimize=True)


def save_contact_sheet(icons: list[Image.Image]) -> None:
    thumb = 360
    gap = 48
    columns = 3
    rows = (len(icons) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (gap * (columns + 1) + thumb * columns, gap * (rows + 1) + thumb * rows),
        (0xE9, 0xE7, 0xE1),
    )
    for index, icon in enumerate(icons):
        row, column = divmod(index, columns)
        position = (gap + column * (thumb + gap), gap + row * (thumb + gap))
        sheet.paste(icon.resize((thumb, thumb), Image.Resampling.LANCZOS), position)
    sheet.save(DESIGN_DIR / "contact-sheet.png", optimize=True)


def save_appearance_sheet(light_icons: list[Image.Image], dark_icons: list[Image.Image]) -> None:
    """Place each Light/Dark pair side by side for visual QA."""
    thumb = 232
    pair_gap = 16
    gap = 44
    columns = 3
    rows = (len(light_icons) + columns - 1) // columns
    cell_width = thumb * 2 + pair_gap
    sheet = Image.new(
        "RGB",
        (gap * (columns + 1) + cell_width * columns, gap * (rows + 1) + thumb * rows),
        (0xD8, 0xD8, 0xDA),
    )
    for index, (light_icon, dark_icon) in enumerate(zip(light_icons, dark_icons, strict=True)):
        row, column = divmod(index, columns)
        x = gap + column * (cell_width + gap)
        y = gap + row * (thumb + gap)
        sheet.paste(light_icon.resize((thumb, thumb), Image.Resampling.LANCZOS), (x, y))
        sheet.paste(dark_icon.resize((thumb, thumb), Image.Resampling.LANCZOS), (x + thumb + pair_gap, y))
    sheet.save(DESIGN_DIR / "appearance-comparison.png", optimize=True)


def main() -> None:
    indexed_icons: list[Image.Image] = []
    light_icons: list[Image.Image] = []
    dark_icons: list[Image.Image] = []
    for raw_filename, master_stem, icon_name, preview_name, family in ICONS:
        source_colors, light_colors, dark_colors = PALETTE_FAMILIES[family]
        indexed = snap_to_palette(RAW_DIR / raw_filename, source_colors)
        indexed_icons.append(indexed)
        light_icon, dark_icon = save_ios_assets(
            indexed,
            master_stem,
            icon_name,
            preview_name,
            light_colors,
            dark_colors,
        )
        light_icons.append(light_icon)
        dark_icons.append(dark_icon)

    for master_stem, icon_name, preview_name, light_name, dark_name, tinted_name in EXACT_ICONS:
        light_icon, dark_icon = save_direct_ios_assets(
            Image.open(RAW_DIR / light_name),
            Image.open(RAW_DIR / dark_name),
            Image.open(RAW_DIR / tinted_name),
            master_stem,
            icon_name,
            preview_name,
        )
        light_icons.append(light_icon)
        dark_icons.append(dark_icon)

    for master_stem, icon_name, preview_name, kind in SIMPLE_ICONS:
        variants = {
            appearance: make_simple_icon(kind, appearance)
            for appearance in ("light", "dark", "tinted")
        }
        variants["light"].save(RAW_DIR / f"{master_stem}.png", optimize=True)
        variants["dark"].save(RAW_DIR / f"{master_stem}-dark.png", optimize=True)
        variants["tinted"].save(RAW_DIR / f"{master_stem}-tinted.png", optimize=True)
        light_icon, dark_icon = save_direct_ios_assets(
            variants["light"],
            variants["dark"],
            variants["tinted"],
            master_stem,
            icon_name,
            preview_name,
        )
        light_icons.append(light_icon)
        dark_icons.append(dark_icon)

    assert len(light_icons) == len(dark_icons) == 9
    watch_icon = render_variant(indexed_icons[0], TV_PALETTE, (1024, 1024))
    save_mac_and_watch(light_icons[0], watch_icon)
    save_tv_assets(indexed_icons[0])
    save_contact_sheet(light_icons)
    save_appearance_sheet(light_icons, dark_icons)


if __name__ == "__main__":
    main()
