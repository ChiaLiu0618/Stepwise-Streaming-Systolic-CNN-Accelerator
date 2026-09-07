#!/usr/bin/env python3
"""Map Accelerator to an external Liberty library, then run STA and a gate test."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reuse-mapping', action='store_true',
                        help='reuse a completed mapping only if inputs and tool versions match')
    args = parser.parse_args()
    dependency = Path(os.environ.get('MIXED_PRECISION_ROOT',
                      str(Path.home() / 'Desktop/Mixed Precision Conference')))
    library = Path(os.environ.get('LIBERTY_PATH', str(dependency /
                   'third_party/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib'))).resolve()
    sta = os.environ.get('STA_BIN', str(dependency / 'third_party/OpenSTA/build/sta'))
    period = float(os.environ.get('CLOCK_PERIOD_NS', '2.0'))
    if not 0 < period < 1000:
        raise ValueError('CLOCK_PERIOD_NS must be between 0 and 1000')
    for tool in ('sv2v', 'yosys', 'iverilog', 'vvp', sta):
        if not shutil.which(tool):
            raise RuntimeError(f'Missing executable: {tool}')
    if not library.is_file():
        raise RuntimeError('Set LIBERTY_PATH to an existing Nangate45 typical Liberty file')
    out = ROOT / 'build/synthesis'
    out.mkdir(parents=True, exist_ok=True)

    def run(command, log):
        print(f'Running {Path(command[0]).name}: {log}', flush=True)
        with (out / log).open('w') as stream:
            result = subprocess.run(command, cwd=out, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode:
            print((out / log).read_text()[-6000:], file=sys.stderr)
            raise RuntimeError(f'Command failed; see {out / log}')

    def version(command):
        return subprocess.check_output(command, text=True).strip()

    provenance = {
        'rtl_sha256': {p.name: sha256(p) for p in sorted((ROOT / 'rtl').glob('*.sv'))},
        'library': str(library), 'library_sha256': sha256(library),
        'yosys': version(['yosys', '-V']), 'sv2v': version(['sv2v', '--version']),
        'opensta': version([sta, '-version']), 'clock_period_ns': period,
        'flow_sha256': sha256(Path(__file__)),
        'abc_driver': 'BUF_X1', 'output_load_ff': 5.0,
        'input_delay_ns': 0.2, 'output_delay_ns': 0.2,
        'input_transition_ns': 0.05, 'clock_uncertainty_ns': 0.05,
    }
    stamp = out / 'mapping_inputs.json'
    if args.reuse_mapping:
        if not stamp.exists() or json.loads(stamp.read_text()) != provenance:
            raise RuntimeError('Mapping inputs changed or no completed mapping exists; rerun without --reuse-mapping')
        if not (out / 'accelerator_mapped.v').exists():
            raise RuntimeError('Mapped netlist missing')
    else:
        stamp.unlink(missing_ok=True)
        run(['sv2v', '-I', str(ROOT / 'rtl'), '--top', 'Accelerator',
             '-w', str(out / 'accelerator.v'), str(ROOT / 'rtl/Accelerator.sv')], 'sv2v.log')
        # Local dependency copy keeps spaces out of synthesis commands; never published.
        shutil.copy2(library, out / 'cells.lib')
        (out / 'abc.constr').write_text('set_driving_cell BUF_X1\nset_load 5.0\n')
        (out / 'synth.ys').write_text(f'''read_liberty -lib cells.lib
read_verilog accelerator.v
hierarchy -check -top Accelerator
synth -top Accelerator -flatten -noabc
dfflibmap -liberty cells.lib
abc -liberty cells.lib -constr abc.constr -D {round(period * 1000)}
clean -purge
check -assert
tee -o area.txt stat -liberty cells.lib
write_verilog -noattr -noexpr -nodec accelerator_mapped.v
write_json accelerator_mapped.json
''')
        run(['yosys', '-Q', '-T', '-l', 'yosys.log', 'synth.ys'], 'console.log')
        stamp.write_text(json.dumps(provenance, indent=2) + '\n')

    # OpenSTA's structural parser does not accept signed wire declarations.
    # The cell-only netlist has no arithmetic expressions: connectivity is unchanged.
    netlist = (out / 'accelerator_mapped.v').read_text()
    sta_netlist = re.sub(r'(?m)^(\s*(?:input|output|wire)) signed\b', r'\1', netlist)
    (out / 'accelerator_sta.v').write_text(sta_netlist)
    (out / 'timing.tcl').write_text(f'''read_liberty cells.lib
read_verilog accelerator_sta.v
link_design Accelerator
create_clock -name core_clk -period {period} [get_ports clk]
set_clock_uncertainty 0.05 [get_clocks core_clk]
set_input_delay -clock core_clk -max 0.2 [get_ports {{instruction* SRAM*}}]
set_input_delay -clock core_clk -min 0.0 [get_ports {{instruction* SRAM*}}]
set_input_transition 0.05 [get_ports {{instruction* SRAM*}}]
set_input_delay -clock core_clk 0.0 [get_ports rst_n]
set_false_path -from [get_ports rst_n]
set_output_delay -clock core_clk -max 0.2 [get_ports {{write_valid write_data*}}]
set_output_delay -clock core_clk -min 0.0 [get_ports {{write_valid write_data*}}]
set_load 5.0 [get_ports {{write_valid write_data*}}]
check_setup -verbose
report_checks -path_delay max -group_path_count 3 -fields {{capacitance slew fanout}} -digits 4
report_clock_min_period -include_port_paths
report_worst_slack -max
report_tns
exit
''')
    run([sta, '-exit', 'timing.tcl'], 'timing.log')
    if re.search(r'^Error:', (out / 'timing.log').read_text(), re.M):
        raise RuntimeError('OpenSTA reported errors; inspect timing.log')

    run(['yosys', '-Q', '-T', '-p',
         'read_liberty -ignore_miss_func cells.lib; write_verilog -noattr cells.v'], 'cells.log')
    run(['sv2v', '-I', str(ROOT / 'rtl'), '--top', 'tb_prefetch',
         '-w', 'prefetch_converted.v', str(ROOT / 'tb/integration/tb_prefetch.sv')], 'tb_sv2v.log')
    converted = (out / 'prefetch_converted.v').read_text()
    begin = converted.index('module tb_prefetch')
    end = converted.index('endmodule', begin) + len('endmodule')
    (out / 'tb_prefetch_gate.v').write_text('`timescale 1ns/1ps\n' + converted[begin:end] + '\n')
    run(['iverilog', '-g2012', '-s', 'tb_prefetch', '-o', 'gate.vvp',
         'cells.v', 'accelerator_mapped.v', 'tb_prefetch_gate.v'], 'gate_compile.log')
    run(['vvp', 'gate.vvp'], 'gate.log')
    gate_log = (out / 'gate.log').read_text()
    if 'PASS: serial/prefetch Conv and FC' not in gate_log or re.search(r'FATAL|ERROR', gate_log):
        raise RuntimeError('Mapped-netlist prefetch test did not pass')
    if gate_log.count('DEMO_WORD') != 20:
        raise RuntimeError('Incomplete mapped-netlist output checks')
    area_text = (out / 'area.txt').read_text()
    area = re.search(r"Chip area for module.*?:\s*([\d.]+)", area_text)
    cells = re.search(r'^\s*(\d+)\s+\S+\s+cells\s*$', area_text, re.M)
    timing = (out / 'timing.log').read_text()
    slack = re.search(r'worst slack max\s+(-?[\d.]+)', timing)
    if not (area and cells and slack):
        raise RuntimeError('Cannot parse synthesis reports')
    summary = {
        'mapped_cell_area_um2': float(area[1]), 'mapped_cells': int(cells[1]),
        'target_period_ns': period, 'worst_setup_slack_ns': float(slack[1]),
        'meets_target_pre_layout': float(slack[1]) >= 0,
        'gate_prefetch_words_checked': 20,
        'netlist_sha256': sha256(out / 'accelerator_mapped.v'),
        'testbench_sha256': sha256(ROOT / 'tb/integration/tb_prefetch.sv'),
        'limits': 'Nangate45 typical, ideal clock, cell-pin loads only; no placement, routing, extracted parasitics or power analysis.',
    }
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    print(f'Reports and dependency copies remain under {out} (ignored by Git).')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
