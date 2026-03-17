# pcb2img

Convert KiCad PCB files into high-quality PNG images from the command line.

<p>
  <img width="400" alt="pps-pd split render" src="https://github.com/user-attachments/assets/47f570db-2a9f-4344-a5fc-3e0c4dcaf992" />
  <img width="400" alt="temp_sense_redesign split render" src="https://github.com/user-attachments/assets/555bfa77-6421-47a8-b558-97e859014da4" />
</p>

---

## Features

- **Split mode** — renders front and back of the board as a single combined image, with the back flipped to match physical orientation
- **Art mode** — stylized single-color trace render on a solid background, great for documentation or wall art
- **Interactive or scripted** — prompts for settings when run without flags, or accepts everything via CLI options
- **Board-aware cropping** — uses the `Edge.Cuts` outline to clip off-board artifacts (stray references, dimension lines, fab layers)
- **Auto-labeled** — front/back views are clearly labeled with properly padded text
- **WSL compatible** — detects `kicad-cli` on both Linux and Windows (via WSL path)

---

## Requirements

| Tool | Version | Install |
|------|---------|---------|
| [KiCad](https://www.kicad.org/download/) | 9.0+ | `kicad-cli` must be on PATH |
| [ImageMagick](https://imagemagick.org/) | 6 or 7 | `sudo apt install imagemagick` |

---

## Usage

```bash
# Interactive — prompts for mode, DPI, layout, colors
./pcb2img.sh board.kicad_pcb

# Split mode (front + back stacked vertically)
./pcb2img.sh board.kicad_pcb -m split

# Split mode (side by side)
./pcb2img.sh board.kicad_pcb -m split -l horizontal

# Art mode (white traces on black)
./pcb2img.sh board.kicad_pcb -m art

# Art mode with custom colors and DPI
./pcb2img.sh board.kicad_pcb -m art --bg "#1a1a2e" --fg "#e94560" -d 800

# Custom output filename
./pcb2img.sh board.kicad_pcb -m split -o render.png
```

---

## Options

```
-o FILE      Output filename (default: <board>_<mode>.png)
-m MODE      Render mode: split or art (default: interactive prompt)
-d DPI       Resolution in dots per inch (default: 600)
-l LAYOUT    Split layout: vertical or horizontal (default: vertical)
--bg HEX     Art mode background color (default: #000000)
--fg HEX     Art mode trace color (default: #FFFFFF)
--layers     Art mode layers (default: F.Cu,B.Cu,Edge.Cuts)
-h           Show help
```

When `-m` is omitted, the script enters interactive mode and prompts for all settings. Press Enter at any prompt to keep the default.

---

## Render Modes

### Split

Renders the front and back of the board and combines them into a single image. The back view is flipped to match how the board looks when you physically flip it toward you.

**Layers rendered:**
- Front — `F.Cu`, `F.Mask`, `Edge.Cuts`
- Back — `B.Cu`, `B.Mask`, `Edge.Cuts`

**Layouts:**
- `vertical` — front on top, back on bottom (default)
- `horizontal` — front on left, back on right

### Art

Exports selected layers in black and white, then recolors traces and background to your chosen colors. Produces a clean, stylized image suitable for prints or documentation.

**Default layers:** `F.Cu`, `B.Cu`, `Edge.Cuts`

You can include any KiCad layer — some useful ones:

| Layer | Description |
|-------|-------------|
| `F.Cu` | Front copper |
| `B.Cu` | Back copper |
| `Edge.Cuts` | Board outline |
| `F.Mask` | Front solder mask |
| `B.Mask` | Back solder mask |
| `In1.Cu` | Inner copper layer 1 |
| `In2.Cu` | Inner copper layer 2 |

---

## Examples

**Split — vertical (default):**
```bash
./pcb2img.sh my_board.kicad_pcb -m split
```

**Split — horizontal:**
```bash
./pcb2img.sh my_board.kicad_pcb -m split -l horizontal
```

**Art — white on black:**
```bash
./pcb2img.sh my_board.kicad_pcb -m art
```

**Art — gold on navy:**
```bash
./pcb2img.sh my_board.kicad_pcb -m art --bg "#0d1b2a" --fg "#ffd700"
```

**Art — front copper only at 300 DPI:**
```bash
./pcb2img.sh my_board.kicad_pcb -m art --layers "F.Cu,Edge.Cuts" -d 300
```

---

## How It Works

1. Copies the `.kicad_pcb` file to a temp directory (avoids path issues with `kicad-cli`)
2. Uses `kicad-cli pcb export svg` to render selected layers to SVG
3. Converts SVG to PNG at the configured DPI via ImageMagick
4. **Split mode:** exports `Edge.Cuts` separately to determine the true board bounding box, then crops both front and back to that box — this eliminates off-board elements like stray reference designators, dimension annotations, and fab layer text. The back image is flipped to match physical orientation, both views are padded to equal width, labeled, and combined.
5. **Art mode:** converts the B&W export to a mask, colorizes traces, and composites over a solid background.
6. Cleans up the temp directory on exit.

---

## Troubleshooting

**`kicad-cli not found`**
Make sure KiCad 9+ is installed and `kicad-cli` is on your PATH. On WSL, the script also checks the default Windows install path.

**`ImageMagick not found`**
```bash
sudo apt install imagemagick
```

**SVG export fails silently**
KiCad's CLI can fail without a clear error. Check that your `.kicad_pcb` file opens correctly in KiCad's GUI. The script copies the file to a temp directory to avoid issues with spaces or special characters in the path.

**Output has security policy errors**
ImageMagick may block SVG conversion by default. Edit `/etc/ImageMagick-6/policy.xml` (or `-7`):
```xml
<!-- Change this line: -->
<policy domain="coder" rights="none" pattern="SVG" />
<!-- To: -->
<policy domain="coder" rights="read" pattern="SVG" />
```

---

## License

MIT
