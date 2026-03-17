#!/usr/bin/env bash
# ============================================================================
#  pcb2img — KiCad PCB to Image Converter
# ============================================================================
#
#  Converts a KiCad PCB file (.kicad_pcb) into a high-quality PNG image.
#
#  Modes:
#    split (default) — Front silkscreen + back copper, combined vertically
#    art             — Stylized single-color traces on solid background
#
#  Requirements:  KiCad 9+ (kicad-cli)  •  ImageMagick
#
#  Usage:
#    ./pcb2img.sh board.kicad_pcb                        # split mode
#    ./pcb2img.sh board.kicad_pcb -m art                 # art mode
#    ./pcb2img.sh board.kicad_pcb -o out.png -d 800      # custom output & DPI
#    ./pcb2img.sh board.kicad_pcb -m split -l horizontal  # side-by-side
#
# ============================================================================

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────

MODE="split"
DPI=600
LAYOUT="vertical"
BG_COLOR="#000000"
TRACE_COLOR="#FFFFFF"
ART_LAYERS="F.Cu,B.Cu,Edge.Cuts"
OUTPUT=""
KICAD_CLI=""
MAGICK=""

# ── Logging ─────────────────────────────────────────────────────────────────

info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; exit 1; }

# ── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Usage: pcb2img.sh <board.kicad_pcb> [options]

Options:
  -o FILE    Output filename (default: <board>_<mode>.png)
  -m MODE    Render mode: split (default) or art
  -d DPI     Resolution (default: 600)
  -l LAYOUT  Split layout: vertical (default) or horizontal
  --bg HEX   Art background color (default: #000000)
  --fg HEX   Art trace color (default: #FFFFFF)
  --layers   Art layers (default: F.Cu,B.Cu,Edge.Cuts)
  -h         Show this help
EOF
    exit 0
}

# ── Find tools ──────────────────────────────────────────────────────────────

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

    info "kicad-cli: $KICAD_CLI"
    info "magick:    $MAGICK"
}

# ── Core helpers ────────────────────────────────────────────────────────────

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

# ── Split render ────────────────────────────────────────────────────────────

render_split() {
    local board="$1" output="$2" tmp="$3"

    # Front: copper + mask + board outline (no silkscreen)
    local front_layers="F.Cu,F.Mask,Edge.Cuts"
    # Back: copper + mask + board outline (no silkscreen)
    local back_layers="B.Cu,B.Mask,Edge.Cuts"

    # ── Export Edge.Cuts only to get the true board bounding box ──
    info "Detecting board outline..."
    export_svg "${tmp}/edge.svg" "Edge.Cuts" "$board"
    svg_to_png "${tmp}/edge.svg" "${tmp}/edge_raw.png"
    # The board outline trimmed gives us the exact board bbox
    local bbox
    bbox=$($MAGICK "${tmp}/edge_raw.png" -fuzz 5% -trim -format '%wx%h%O' info:)
    info "Board bbox: $bbox"

    # ── Export front ──
    info "Rendering front..."
    export_svg "${tmp}/front.svg" "$front_layers" "$board"
    svg_to_png "${tmp}/front.svg" "${tmp}/front_raw.png"
    # Crop to board bbox (clips off-board refs like R7, dimension arrows)
    $MAGICK "${tmp}/front_raw.png" -crop "$bbox" +repage "${tmp}/front.png"

    # ── Export back (flipped vertically — like lifting the board upward) ──
    info "Rendering back..."
    export_svg "${tmp}/back.svg" "$back_layers" "$board"
    svg_to_png "${tmp}/back.svg" "${tmp}/back_raw.png"
    # Crop to same board bbox, then vertical flip
    $MAGICK "${tmp}/back_raw.png" -crop "$bbox" +repage -flip "${tmp}/back.png"

    # ── Normalize to same width ──
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

    # ── Add labels with generous padding (prevents clipping) ──
    local label_size=$(( tw / 35 ))
    (( label_size < 16 )) && label_size=16
    (( label_size > 40 )) && label_size=40
    # Total pad = space above text + text height + space below text
    local pad_top=$(( label_size * 2 ))
    # Vertical offset to center text within the padded strip
    local text_offset=$(( (pad_top - label_size) / 2 ))

    for side in front back; do
        local label
        [[ "$side" == "front" ]] && label="FRONT" || label="BACK"

        $MAGICK "${tmp}/${side}_pad.png" \
            -gravity North -background white -splice "0x${pad_top}" \
            -gravity North -pointsize "$label_size" \
            -fill "#444444" \
            -annotate "+0+${text_offset}" "$label" \
            "${tmp}/${side}_label.png"
    done

    # ── Combine ──
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

# ── Art render ──────────────────────────────────────────────────────────────

render_art() {
    local board="$1" output="$2" tmp="$3"

    info "Exporting B&W SVG..."
    export_svg "${tmp}/art.svg" "$ART_LAYERS" "$board" --black-and-white

    info "Converting to PNG..."
    svg_to_png "${tmp}/art.svg" "${tmp}/art_raw.png"

    info "Applying colors ($TRACE_COLOR on $BG_COLOR)..."
    $MAGICK "${tmp}/art_raw.png" \
        -grayscale Rec709Luminance -threshold 50% "${tmp}/mask.png"

    # Traces = dark pixels in the original (white after negate)
    $MAGICK "${tmp}/mask.png" -negate \
        -fill "$TRACE_COLOR" -colorize 100 "${tmp}/trace.png"

    # Composite: colored traces over solid background
    $MAGICK "${tmp}/trace.png" "${tmp}/mask.png" \
        -compose CopyOpacity -composite "${tmp}/alpha.png"

    local dims
    dims=$(identify -format '%wx%h' "${tmp}/alpha.png")
    $MAGICK -size "$dims" "xc:${BG_COLOR}" \
        "${tmp}/alpha.png" -compose Over -composite "$output"
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    # Parse args
    local input=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage ;;
            -o)           OUTPUT="$2"; shift 2 ;;
            -m)           MODE="$2"; shift 2 ;;
            -d)           DPI="$2"; shift 2 ;;
            -l)           LAYOUT="$2"; shift 2 ;;
            --bg)         BG_COLOR="$2"; shift 2 ;;
            --fg)         TRACE_COLOR="$2"; shift 2 ;;
            --layers)     ART_LAYERS="$2"; shift 2 ;;
            -*)           die "Unknown option: $1" ;;
            *)
                [[ -z "$input" ]] && input="$1" || die "Unexpected argument: $1"
                shift ;;
        esac
    done

    [[ -z "$input" ]] && die "No input file. Run with -h for usage."
    [[ -f "$input" ]] || die "File not found: $input"
    [[ "$MODE" == "split" || "$MODE" == "art" ]] || die "Invalid mode: $MODE (use split or art)"

    # Default output name
    local base
    base=$(basename "$input" .kicad_pcb)
    OUTPUT="${OUTPUT:-${base}_${MODE}.png}"

    echo ""
    echo "  pcb2img — KiCad PCB → PNG"
    echo ""
    info "Input:  $input"
    info "Output: $OUTPUT"
    info "Mode:   $MODE  |  DPI: $DPI"

    find_tools

    # Work in a temp dir (avoids path issues with kicad-cli)
    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '${tmp}'" EXIT

    local board="${tmp}/board.kicad_pcb"
    cp "$input" "$board"

    case "$MODE" in
        split) render_split "$board" "$OUTPUT" "$tmp" ;;
        art)   render_art   "$board" "$OUTPUT" "$tmp" ;;
    esac

    echo ""
    info "Done! → $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
    echo ""
}

main "$@"