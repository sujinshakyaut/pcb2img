# pcb2img

Convert KiCad `.kicad_pcb` files to PNG — front and back combined in one image.

## Requirements

- [KiCad 9+](https://www.kicad.org/download/) (`kicad-cli` on PATH)
- [ImageMagick](https://imagemagick.org/) (`sudo apt install imagemagick`)

## Usage

```bash
./pcb2img.sh board.kicad_pcb                    # stacked vertically
./pcb2img.sh board.kicad_pcb -l horizontal      # side by side
./pcb2img.sh board.kicad_pcb -d 800 -o out.png  # custom DPI & filename
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-o FILE` | Output filename | `<board>.png` |
| `-d DPI` | Resolution | `600` |
| `-l LAYOUT` | `vertical` or `horizontal` | `vertical` |

## How it works

1. Exports `Edge.Cuts` to determine the board bounding box
2. Renders front (`F.Cu`, `F.Mask`, `Edge.Cuts`) and back (`B.Cu`, `B.Mask`, `Edge.Cuts`) layers
3. Crops both to the board outline, removing off-board artifacts
4. Flips the back vertically to match physical orientation
5. Labels, pads, and combines into one image

## Example

<img width="200" height="400" alt="pps-pd_split" src="https://github.com/user-attachments/assets/feec5fa5-acc8-407c-87d3-6fd02c0e6f31" />
