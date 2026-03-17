# pcb2img
Convert KiCad PCB files into high-quality PNG images from the command line.

## Requirements

[KiCad 9+](https://www.kicad.org/download/) (`kicad-cli`)
[ImageMagick](https://imagemagick.org/) (`convert` or `magick`)

```bash
# Ubuntu / WSL
sudo add-apt-repository ppa:kicad/kicad-9.0-releases
sudo apt update && sudo apt install kicad imagemagick
```

## Usage

```bash
./pcb2img.sh board.kicad_pcb              # interactive, outputs board_art.png
./pcb2img.sh board.kicad_pcb render.png   # custom output filename
```

The script prompts for mode, DPI, colors, and layout. Press Enter to accept defaults.

## Examples

### Split (vertical)
```
Mode: split  |  Layout: vertical  |  DPI: 600
```

Renders front and back views stacked vertically with FRONT/BACK labels, aligned and padded to the same dimensions.

### Art

```
Mode: art  |  Trace: #FFFFFF  |  Background: #000000  |  Layers: F.Cu,B.Cu,Edge.Cuts
```

Exports a black-and-white SVG, then recolors traces and background to your chosen colors.

## Options

| Setting | Default | Description |
|---------|---------|-------------|
| Mode | `split` | `art` or `split` |
| DPI | `600` | Image resolution |
| Layout | `vertical` | Split only: `vertical` or `horizontal` |
| Background | `#000000` | Art only: background color |
| Trace color | `#FFFFFF` | Art only: trace/copper color |
| Layers | `F.Cu,B.Cu,Edge.Cuts` | Art only: comma-separated layer list |

## How It Works

1. Copies the PCB to a temp directory (avoids path issues with spaces)
2. Calls `kicad-cli pcb export svg` to generate vector output
3. Converts SVG → PNG via ImageMagick at the requested DPI
4. **Art mode**: thresholds to B&W, masks traces, composites with chosen colors
5. **Split mode**: renders front/back separately, pads to equal size, labels, and appends


## Examples
<img width="400" height="300" alt="pps-pd_art" src="https://github.com/user-attachments/assets/47f570db-2a9f-4344-a5fc-3e0c4dcaf992" />

<img width="400" height="600" alt="temp_sense_redesign_art" src="https://github.com/user-attachments/assets/555bfa77-6421-47a8-b558-97e859014da4" />
