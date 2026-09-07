#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
usage() {
    cat <<'HELP'
Usage: ./run.sh [regfiles|controller|prefetch|triangle|systolic|functional|network|all|help]
  regfiles    Byte-masked shared weight storage test (Icarus Verilog)
  controller  Independent packet decoder and pipeline test (Verilator)
  prefetch    Serial versus overlapped Conv/FC test (Verilator)
  triangle    Triangle buffer test (Verilator)
  systolic    Systolic array test (Verilator)
  functional  Accelerator functional test (Verilator; default)
  network     Run CONV1 -> CONV2 -> CONV3 -> FC (Verilator)
  all         Run every test above
Outputs: build/<target>/; network feature maps: build/network/run.XXXXXX/
HELP
}
need() { command -v "$1" >/dev/null || { echo "Missing required tool: $1" >&2; exit 1; }; }
check_result() {
    local log="$1"
    if grep -Eiq 'FAIL|Error:|Error parsing|%Error|FATAL' "$log" ||
       ! grep -Eq 'PASS:|You have passed all patterns!' "$log"; then
        tail -n 30 "$log" >&2
        echo "Test failed; see $log" >&2
        exit 1
    fi
}
run_verilator() {
    local top="$1" source="$2" target="$3" run_dir="$4"
    local out="$ROOT/build/$target"
    need verilator
    need make
    mkdir -p "$out" "$run_dir"
    echo "Building $top ..."
    if ! verilator --binary --timing -Wno-fatal -j 4 \
        -MAKEFLAGS 'CFG_CXXFLAGS_COROUTINES=-std=c++20' \
        -I"$ROOT/rtl" --top-module "$top" --Mdir "$out/obj" \
        "$ROOT/$source" > "$out/build.log" 2>&1; then
        tail -n 30 "$out/build.log" >&2
        exit 1
    fi
    if ! (cd "$run_dir" && "$out/obj/V$top") > "$out/run.log" 2>&1; then
        tail -n 30 "$out/run.log" >&2
        echo "Simulation failed; see $out/run.log" >&2
        exit 1
    fi
    check_result "$out/run.log"
    echo "PASS: $top ($out/run.log)"
    if [[ "$top" == tb_prefetch ]]; then
        grep 'DEMO_SUMMARY' "$out/run.log"
    fi
}
regfiles() {
    need iverilog
    need vvp
    local out="$ROOT/build/regfiles"
    mkdir -p "$out"
    iverilog -g2012 -I "$ROOT/rtl" -s tb_regfiles -o "$out/test.vvp" "$ROOT/tb/unit/tb_regfiles.sv"
    vvp "$out/test.vvp" > "$out/run.log" 2>&1
    check_result "$out/run.log"
    echo "PASS: tb_regfiles ($out/run.log)"
}
network() {
    local work
    mkdir -p "$ROOT/build/network"
    work="$(mktemp -d "$ROOT/build/network/run.XXXXXX")"
    cp "$ROOT"/data/*.txt "$work/"
    local layer
    for layer in CONV1 CONV2 CONV3 FC; do
        run_verilator "tb_$layer" "tb/layers/tb_$layer.sv" "network/$layer" "$work"
    done
    echo "Feature maps: $work"
}
run_target() {
    case "$1" in
        regfiles) regfiles ;;
        controller) run_verilator tb_Controller tb/unit/tb_Controller.sv controller "$ROOT/build/controller/run" ;;
        prefetch) run_verilator tb_prefetch tb/integration/tb_prefetch.sv prefetch "$ROOT/build/prefetch/run" ;;
        triangle) run_verilator tb_Triangle_Buffer tb/unit/tb_Triangle_Buffer.sv triangle "$ROOT/build/triangle/run" ;;
        systolic) run_verilator tb_Systolic_Array tb/unit/tb_Systolic_Array.sv systolic "$ROOT/build/systolic/run" ;;
        functional) run_verilator tb_accelerator_functional tb/integration/tb_accelerator_functional.sv functional "$ROOT/build/functional/run" ;;
        network) network ;;
        all) for target in regfiles controller prefetch triangle systolic functional network; do run_target "$target"; done ;;
        help|-h|--help) usage ;;
        *) usage >&2; exit 2 ;;
    esac
}
if (( $# > 1 )); then usage >&2; exit 2; fi
run_target "${1:-functional}"
