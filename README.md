# PCB2IMG

Turn KiCad PCB files into high-resolution art. White traces on black, custom palettes, wall-ready output in a single command.

```bash
./pcb2img my_board.kicad_pcb
./pcb2img my_board.kicad_pcb artwork.png
```

---

## How it works

```
.kicad_pcb  →  kicad-cli (SVG)  →  ImageMagick (PNG @ DPI)  →  colorized output
```

1. **Export** — `kicad-cli` renders the selected layers to SVG
2. **Rasterize** — ImageMagick converts the SVG to PNG at your chosen DPI
3. **Colorize** — traces and background are replaced with your hex colors

---

## Requirements

| Tool | Version | Install |
|------|---------|---------|
| KiCad | 7+ | [kicad.org/download](https://www.kicad.org/download/) |
| ImageMagick | any | `sudo apt install imagemagick` / `brew install imagemagick` |
| bash | 4+ | pre-installed on Linux/macOS |

---

## Usage

```bash
# Basic — prompts for colors and settings interactively
./pcb2img my_board.kicad_pcb

# With explicit output name
./pcb2img my_board.kicad_pcb artwork.png

# Help
./pcb2img --help
```

If no output name is given, the file is saved as `<input_name>_art.png`.

---

## Interactive settings

Each run prompts for:

| Setting | Default | Notes |
|---------|---------|-------|
| Background color | `#000000` | Any hex color or name |
| Trace color | `#FFFFFF` | Any hex color or name |
| DPI | `600` | Higher = larger file, more detail |
| Layers | `F.Cu,B.Cu,Edge.Cuts` | Comma-separated list |

Press **Enter** at any prompt to keep the default.

---

## Supported layers

| Layer | Description |
|-------|-------------|
| `F.Cu` | Front copper |
| `B.Cu` | Back copper |
| `Edge.Cuts` | Board outline |
| `F.SilkS` | Front silkscreen |
| `B.SilkS` | Back silkscreen |
| `F.Fab` | Front fabrication |
| `B.Fab` | Back fabrication |
| `F.Paste` | Front paste mask |
| `B.Paste` | Back paste mask |

---

## Examples

```bash
# Classic: white traces on black
./pcb2img board.kicad_pcb
# → Background: #000000, Traces: #FFFFFF

# Warm: copper traces on dark background
./pcb2img board.kicad_pcb copper.png
# → Background: #1a1008, Traces: #e8803a

# Front copper only, ultra high-res
./pcb2img board.kicad_pcb front_only.png
# → Layers: F.Cu, DPI: 1200

# All layers including silkscreen
./pcb2img board.kicad_pcb full.png
# → Layers: F.Cu,B.Cu,Edge.Cuts,F.SilkS,B.SilkS
```

---

## License

MIT
