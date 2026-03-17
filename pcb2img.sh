#!/usr/bin/env bash

#  Converts a KiCad PCB file (.kicad_pcb) into a high-quality PNG image.
#
#  Render modes:
#    art   — Stylized traces with custom colors
#    split — Front & back views combined (stacked or side-by-side)
#
#  Requirements:  KiCad 9+  •  ImageMagick
#
#  Usage:
#    ./pcb2img.sh  board.kicad_pcb
#    ./pcb2img.sh  board.kicad_pcb  output.png
#
# ============================================================================

set -euo pipefail


DEFAULT_MODE="split"
DEFAULT_BG_COLOR="#000000"
DEFAULT_TRACE_COLOR="#FFFFFF"
DEFAULT_DPI=600
DEFAULT_ART_LAYERS="F.Cu,B.Cu,Edge.Cuts"
DEFAULT_SPLIT_LAYERS="F.Cu,F.SilkS,F.Mask,Edge.Cuts"

KICAD_CLI=""
MAGICK_CMD=""

info() { echo -e "\033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

show_help() {
    cat << 'EOF'

  pcb2img — KiCad PCB to Image Converter

  USAGE:
      ./pcb2img.sh <board.kicad_pcb> [output.png]

  RENDER MODES:
      art   — Stylized single-color traces on solid background
      split — Front & back combined into one image

EOF
    exit 0
}

# Export SVG via kicad-cli
kicad_export_svg() {
    local out_svg="$1" layers="$2" input="$3"
    shift 3
    "$KICAD_CLI" pcb export svg \
        --output "$out_svg" \
        --layers "$layers" \
        --exclude-drawing-sheet \
        --page-size-mode 2 \
        "$@" "$input" 2>&1 || true
    [[ -f "$out_svg" ]] || die "KiCad SVG export failed."
}

# Convert SVG → PNG at configured DPI
svg_to_png() {
    local svg="$1" png="$2"
    $MAGICK_CMD -density "$DPI" -background white "$svg" -flatten "$png"
    [[ -f "$png" ]] || die "SVG to PNG conversion failed."
}


check_requirements() {
    local missing=0

    if command -v kicad-cli &>/dev/null; then
        KICAD_CLI="kicad-cli"
    elif [[ -f "/mnt/c/Program Files/KiCad/9.0/bin/kicad-cli.exe" ]]; then
        KICAD_CLI="/mnt/c/Program Files/KiCad/9.0/bin/kicad-cli.exe"
    else
        warn "kicad-cli not found! Install KiCad 9+ from https://www.kicad.org/download/"
        missing=1
    fi

    if command -v magick &>/dev/null; then
        MAGICK_CMD="magick"
    elif command -v convert &>/dev/null; then
        MAGICK_CMD="convert"
    else
        warn "ImageMagick not found! sudo apt install imagemagick"
        missing=1
    fi

    [[ $missing -eq 1 ]] && die "Missing required tools."
    info "kicad-cli : ${KICAD_CLI}"
    info "magick    : ${MAGICK_CMD}"
}

ask_settings() {
    echo ""
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │  Render settings (Enter = keep default)  │"
    echo "  └──────────────────────────────────────────┘"
    echo ""
    echo "  Modes:  1) art   2) split"
    read -rp "  Mode [${DEFAULT_MODE}]: " input_mode
    RENDER_MODE="${input_mode:-$DEFAULT_MODE}"
    [[ "$RENDER_MODE" == "1" ]] && RENDER_MODE="art"
    [[ "$RENDER_MODE" == "2" ]] && RENDER_MODE="split"

    # DPI
    read -rp "  DPI [${DEFAULT_DPI}]: " input_dpi
    DPI="${input_dpi:-$DEFAULT_DPI}"

    # Split-specific settings
    SPLIT_LAYOUT="vertical"
    if [[ "$RENDER_MODE" == "split" ]]; then
        echo "  Layout:  1) vertical   2) horizontal"
        read -rp "  Layout [vertical]: " input_layout
        SPLIT_LAYOUT="${input_layout:-vertical}"
        [[ "$SPLIT_LAYOUT" == "1" ]] && SPLIT_LAYOUT="vertical"
        [[ "$SPLIT_LAYOUT" == "2" ]] && SPLIT_LAYOUT="horizontal"
    fi

    # Art-specific settings
    BG_COLOR="" ; TRACE_COLOR="" ; LAYERS=""
    if [[ "$RENDER_MODE" == "art" ]]; then
        read -rp "  Background color [${DEFAULT_BG_COLOR}]: " input_bg
        BG_COLOR="${input_bg:-$DEFAULT_BG_COLOR}"
        read -rp "  Trace color [${DEFAULT_TRACE_COLOR}]: " input_trace
        TRACE_COLOR="${input_trace:-$DEFAULT_TRACE_COLOR}"
        echo "  Layers: F.Cu  B.Cu  Edge.Cuts  F.SilkS  B.SilkS"
        read -rp "  Layers [${DEFAULT_ART_LAYERS}]: " input_layers
        LAYERS="${input_layers:-$DEFAULT_ART_LAYERS}"
    fi

    echo ""
    info "Mode: ${RENDER_MODE}  |  DPI: ${DPI}"
    [[ "$RENDER_MODE" == "split" ]] && info "Layout: ${SPLIT_LAYOUT}"
    [[ "$RENDER_MODE" == "art" ]]   && info "Colors: ${TRACE_COLOR} on ${BG_COLOR}  |  Layers: ${LAYERS}"
    echo ""
}

render_pcb() {
    local input_file
    input_file="$(realpath "$1")"
    local output_file="$2"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '${tmp_dir}'" EXIT
    info "Temp: ${tmp_dir}"

    # Copy to temp dir (kicad-cli can't handle spaces in paths)
    local board="${tmp_dir}/board.kicad_pcb"
    cp "$input_file" "$board"

    case "$RENDER_MODE" in
        art)   render_art   "$board" "$output_file" "$tmp_dir" ;;
        split) render_split "$board" "$output_file" "$tmp_dir" ;;
        *)     die "Unknown mode: $RENDER_MODE" ;;
    esac

    info "Output: ${output_file} ($(du -h "$output_file" | cut -f1))"
}


render_art() {
    local board="$1" output="$2" tmp="$3"
    local svg="${tmp}/export.svg" png="${tmp}/export.png"

    info "Exporting B&W SVG..."
    kicad_export_svg "$svg" "$LAYERS" "$board" --black-and-white

    info "Converting to PNG..."
    svg_to_png "$svg" "$png"

    info "Applying colors (${TRACE_COLOR} on ${BG_COLOR})..."

    $MAGICK_CMD "$png" -grayscale Rec709Luminance -threshold 50% "${tmp}/mask.png"
    $MAGICK_CMD "${tmp}/mask.png" -negate "${tmp}/mask_inv.png"
    $MAGICK_CMD "${tmp}/mask_inv.png" -fill "${TRACE_COLOR}" -colorize 100 "${tmp}/trace.png"
    $MAGICK_CMD "${tmp}/trace.png" "${tmp}/mask_inv.png" \
        -compose CopyOpacity -composite "${tmp}/alpha.png"
    $MAGICK_CMD -size "$(identify -format '%wx%h' "${tmp}/alpha.png")" \
        "xc:${BG_COLOR}" "${tmp}/alpha.png" \
        -compose Over -composite "$output"
}


render_split() {
    local board="$1" output="$2" tmp="$3"

    local front_layers="F.Cu,F.SilkS,F.Mask,Edge.Cuts"
    local back_layers="B.Cu,B.SilkS,B.Mask,Edge.Cuts"

    # --- Front ---
    info "Rendering front..."
    kicad_export_svg "${tmp}/front.svg" "$front_layers" "$board"
    svg_to_png "${tmp}/front.svg" "${tmp}/front_raw.png"
    $MAGICK_CMD "${tmp}/front_raw.png" -trim +repage "${tmp}/front.png"

    # --- Back (mirrored as if flipping the board) ---
    info "Rendering back..."
    kicad_export_svg "${tmp}/back.svg" "$back_layers" "$board"
    svg_to_png "${tmp}/back.svg" "${tmp}/back_raw.png"
    $MAGICK_CMD "${tmp}/back_raw.png" -trim +repage -flop "${tmp}/back.png"

    # --- Pad both to same dimensions for alignment ---
    local fw fh bw bh tw th
    fw=$(identify -format '%w' "${tmp}/front.png")
    fh=$(identify -format '%h' "${tmp}/front.png")
    bw=$(identify -format '%w' "${tmp}/back.png")
    bh=$(identify -format '%h' "${tmp}/back.png")
    tw=$(( fw > bw ? fw : bw ))
    th=$(( fh > bh ? fh : bh ))

    $MAGICK_CMD "${tmp}/front.png" \
        -gravity center -background white -extent "${tw}x${th}" \
        "${tmp}/front_pad.png"
    $MAGICK_CMD "${tmp}/back.png" \
        -gravity center -background white -extent "${tw}x${th}" \
        "${tmp}/back_pad.png"

    # --- Add labels ---
    local label_size=$(( tw / 30 ))
    [[ $label_size -lt 16 ]] && label_size=16
    local label_pad=$(( label_size + 16 ))

    $MAGICK_CMD "${tmp}/front_pad.png" \
        -gravity North -background white -splice "0x${label_pad}" \
        -gravity North -pointsize "$label_size" -fill "#555555" \
        -annotate +0+4 "FRONT" \
        "${tmp}/front_final.png"

    $MAGICK_CMD "${tmp}/back_pad.png" \
        -gravity North -background white -splice "0x${label_pad}" \
        -gravity North -pointsize "$label_size" -fill "#555555" \
        -annotate +0+4 "BACK" \
        "${tmp}/back_final.png"

    # --- Combine ---
    info "Combining (${SPLIT_LAYOUT})..."
    if [[ "$SPLIT_LAYOUT" == "horizontal" ]]; then
        $MAGICK_CMD "${tmp}/front_final.png" "${tmp}/back_final.png" \
            +append -bordercolor white -border 20 "$output"
    else
        $MAGICK_CMD "${tmp}/front_final.png" "${tmp}/back_final.png" \
            -append -bordercolor white -border 20 "$output"
    fi
}

main() {
    echo ""
    echo "  ╔════════════════════════════════╗"
    echo "  ║   pcb2img — KiCad PCB to PNG   ║"
    echo "  ╚════════════════════════════════╝"
    echo ""

    [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && show_help

    local input="${1:-}"
    [[ -z "$input" ]] && die "No input file. Usage: ./pcb2img.sh <board.kicad_pcb>"
    [[ -f "$input" ]] || die "File not found: ${input}"

    local base
    base=$(basename "$input" .kicad_pcb)
    local output="${2:-${base}_art.png}"

    info "Input  : ${input}"
    info "Output : ${output}"

    check_requirements
    ask_settings
    render_pcb "$input" "$output"

    echo ""
    echo "  Done! ✓"
    echo ""
}

main "$@"
