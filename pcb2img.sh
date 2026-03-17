#!/usr/bin/env bash


#  Renders front & back of a KiCad PCB as a combined PNG image.
#  The back is flipped vertically to match physical orientation.
#
#  Usage:
#    ./pcb2img.sh board.kicad_pcb
#    ./pcb2img.sh board.kicad_pcb -o out.png -d 800
#    ./pcb2img.sh board.kicad_pcb -l horizontal


set -euo pipefail

DPI=600
LAYOUT="vertical"
OUTPUT=""
KICAD_CLI=""
MAGICK=""

info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: pcb2img.sh <board.kicad_pcb> [options]

Options:
  -o FILE    Output filename (default: <board>.png)
  -d DPI     Resolution (default: 600)
  -l LAYOUT  vertical (default) or horizontal
  -h         Show this help
EOF
    exit 0
}

find_tools() {
    if command -v kicad-cli &>/dev/null; then
        KICAD_CLI="kicad-cli"
    elif [[ -f "/mnt/c/Program Files/KiCad/9.0/bin/kicad-cli.exe" ]]; then
        KICAD_CLI="/mnt/c/Program Files/KiCad/9.0/bin/kicad-cli.exe"
    else
        die "kicad-cli not found. Install KiCad 9+ from https://www.kicad.org/download/"
    fi

    if command -v magick &>/dev/null; then
        MAGICK="magick"
    elif command -v convert &>/dev/null; then
        MAGICK="convert"
    else
        die "ImageMagick not found. Install: sudo apt install imagemagick"
    fi
}

export_svg() {
    local svg="$1" layers="$2" board="$3"
    shift 3
    "$KICAD_CLI" pcb export svg \
        --output "$svg" \
        --layers "$layers" \
        --exclude-drawing-sheet \
        --page-size-mode 2 \
        "$@" "$board" 2>&1 || true
    [[ -f "$svg" ]] || die "SVG export failed for layers: $layers"
}

svg_to_png() {
    local svg="$1" png="$2"
    $MAGICK -density "$DPI" -background white "$svg" -flatten "$png"
    [[ -f "$png" ]] || die "SVG→PNG conversion failed: $svg"
}

render() {
    local board="$1" output="$2" tmp="$3"

    local front_layers="F.Cu,F.Mask,Edge.Cuts"
    local back_layers="B.Cu,B.Mask,Edge.Cuts"

    # Board bounding box from Edge.Cuts
    info "Detecting board outline..."
    export_svg "${tmp}/edge.svg" "Edge.Cuts" "$board"
    svg_to_png "${tmp}/edge.svg" "${tmp}/edge.png"
    local bbox
    bbox=$($MAGICK "${tmp}/edge.png" -fuzz 5% -trim -format '%wx%h%O' info:)

    # Front
    info "Rendering front..."
    export_svg "${tmp}/front.svg" "$front_layers" "$board"
    svg_to_png "${tmp}/front.svg" "${tmp}/front_raw.png"
    $MAGICK "${tmp}/front_raw.png" -crop "$bbox" +repage "${tmp}/front.png"

    # Back (flipped vertically)
    info "Rendering back..."
    export_svg "${tmp}/back.svg" "$back_layers" "$board"
    svg_to_png "${tmp}/back.svg" "${tmp}/back_raw.png"
    $MAGICK "${tmp}/back_raw.png" -crop "$bbox" +repage -flip "${tmp}/back.png"

    # Pad to same width
    local fw bw tw fh bh
    fw=$(identify -format '%w' "${tmp}/front.png")
    bw=$(identify -format '%w' "${tmp}/back.png")
    fh=$(identify -format '%h' "${tmp}/front.png")
    bh=$(identify -format '%h' "${tmp}/back.png")
    tw=$(( fw > bw ? fw : bw ))

    $MAGICK "${tmp}/front.png" -gravity center -background white \
        -extent "${tw}x${fh}" "${tmp}/front_pad.png"
    $MAGICK "${tmp}/back.png" -gravity center -background white \
        -extent "${tw}x${bh}" "${tmp}/back_pad.png"

    # Labels
    local label_size=$(( tw / 35 ))
    (( label_size < 16 )) && label_size=16
    (( label_size > 40 )) && label_size=40
    local pad=$(( label_size * 2 ))
    local offset=$(( (pad - label_size) / 2 ))

    for side in front back; do
        local label
        [[ "$side" == "front" ]] && label="FRONT" || label="BACK"
        $MAGICK "${tmp}/${side}_pad.png" \
            -gravity North -background white -splice "0x${pad}" \
            -gravity North -pointsize "$label_size" \
            -fill "#444444" -annotate "+0+${offset}" "$label" \
            "${tmp}/${side}_label.png"
    done

    # Combine
    local gap=30
    info "Combining ($LAYOUT)..."
    if [[ "$LAYOUT" == "horizontal" ]]; then
        $MAGICK "${tmp}/front_label.png" \
            \( -size "${gap}x1" xc:white \) \
            "${tmp}/back_label.png" \
            +append -bordercolor white -border 20 "$output"
    else
        $MAGICK "${tmp}/front_label.png" \
            \( -size "1x${gap}" xc:white \) \
            "${tmp}/back_label.png" \
            -append -bordercolor white -border 20 "$output"
    fi
}

main() {
    local input=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -o)        OUTPUT="$2"; shift 2 ;;
            -d)        DPI="$2"; shift 2 ;;
            -l)        LAYOUT="$2"; shift 2 ;;
            -*)        die "Unknown option: $1" ;;
            *)
                [[ -z "$input" ]] && input="$1" || die "Unexpected argument: $1"
                shift ;;
        esac
    done

    [[ -z "$input" ]] && die "No input file. Run with -h for usage."
    [[ -f "$input" ]] || die "File not found: $input"

    local base
    base=$(basename "$input" .kicad_pcb)
    OUTPUT="${OUTPUT:-${base}.png}"

    info "Input:  $input"
    info "Output: $OUTPUT"
    info "DPI: $DPI  |  Layout: $LAYOUT"

    find_tools

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '${tmp}'" EXIT

    local board="${tmp}/board.kicad_pcb"
    cp "$input" "$board"

    render "$board" "$OUTPUT" "$tmp"

    info "Done! → $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
}

main "$@"
