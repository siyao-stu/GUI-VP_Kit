#!/usr/bin/env python3

import argparse
import re
import shlex
import subprocess
import sys
from pathlib import Path

try:
    import gdb
except ImportError:
    gdb = None


WORKSPACE_ROOT = Path(__file__).resolve().parents[1]
EDK2_BUILD_ROOT = WORKSPACE_ROOT / 'edk2' / 'Build' / 'RiscVVirtQemu' / 'DEBUG_GCC'
RISCV64_DEBUG_DIR = EDK2_BUILD_ROOT / 'RISCV64'
FV_DIR = EDK2_BUILD_ROOT / 'FV'
GUID_XREF = FV_DIR / 'Guid.xref'
DXE_FV_TXT = FV_DIR / 'DXEFV.Fv.txt'
MAIN_FV_TXT = FV_DIR / 'FVMAIN_COMPACT.Fv.txt'

DEFAULT_DXE_FV_BASE = 0x80200000
DEFAULT_SEC_FV_BASE = 0x80200000
FFS_PE_IMAGE_HEADER_DELTA = 0x48

SECTION_RE = re.compile(
    r'^\s*\d+\s+(?P<name>\.\S+)\s+[0-9a-fA-F]+\s+(?P<vma>[0-9a-fA-F]+)\s+'
)
FV_TXT_RE = re.compile(r'^0x(?P<offset>[0-9a-fA-F]+)\s+(?P<guid>[0-9A-Fa-f-]+)$')
LOG_DXECORE_RE = re.compile(r'^Loading DxeCore at 0x(?P<addr>[0-9A-Fa-f]+)\b')
LOG_DRIVER_RE = re.compile(
    r'^Loading driver at 0x(?P<addr>[0-9A-Fa-f]+)\s+EntryPoint=0x[0-9A-Fa-f]+\s+(?P<name>\S+\.efi)\b'
)


def parse_int(value):
    return int(value, 0)


def quote_path(path):
    return shlex.quote(str(path))


def load_guid_xref():
    guid_map = {}
    for line in GUID_XREF.read_text().splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        guid, target = parts
        guid = guid.upper()
        target = target.strip()
        if target.endswith('.Fv'):
            guid_map[guid] = Path(target).stem
        else:
            guid_map[guid] = target
    return guid_map


def load_debug_files():
    debug_map = {}
    for debug_file in RISCV64_DEBUG_DIR.glob('*.debug'):
        debug_map[debug_file.stem] = debug_file
    return debug_map


def read_section_vmas(debug_file):
    result = subprocess.run(
        ['objdump', '-h', str(debug_file)],
        check=True,
        capture_output=True,
        text=True,
    )
    sections = {}
    for line in result.stdout.splitlines():
        match = SECTION_RE.match(line)
        if not match:
            continue
        name = match.group('name')
        vma = int(match.group('vma'), 16)
        sections[name] = vma
    return sections


def parse_fv_txt(fv_txt, guid_map):
    entries = []
    for line in fv_txt.read_text().splitlines():
        match = FV_TXT_RE.match(line.strip())
        if not match:
            continue
        guid = match.group('guid').upper()
        module_name = guid_map.get(guid)
        if module_name is None:
            continue
        entries.append((int(match.group('offset'), 16), guid, module_name))
    return entries


def parse_log_loads(log_path):
    entries = []
    for line in log_path.read_text().splitlines():
        line = line.strip()
        match = LOG_DXECORE_RE.match(line)
        if match:
            addr = int(match.group('addr'), 16)
            entries.append(('DxeCore', addr))
            continue

        match = LOG_DRIVER_RE.match(line)
        if not match:
            continue
        addr = int(match.group('addr'), 16)
        name = match.group('name')
        module = Path(name).stem
        entries.append((module, addr))

    return entries


def build_symbol_command(debug_file, image_base, sections):
    text_vma = sections.get('.text')
    if text_vma is None:
        return None

    command = (
        f'add-symbol-file {quote_path(debug_file)} {hex(image_base + text_vma)}'
    )
    data_vma = sections.get('.data')
    if data_vma is not None:
        command += f' -s .data {hex(image_base + data_vma)}'
    return command


def collect_commands(sec_fv_base, dxe_fv_base, log_path=None):
    guid_map = load_guid_xref()
    debug_map = load_debug_files()
    commands = []
    seen_modules = set()

    if log_path is not None:
        for module_name, image_base in parse_log_loads(log_path):
            debug_file = debug_map.get(module_name)
            if debug_file is None:
                continue
            sections = read_section_vmas(debug_file)
            command = build_symbol_command(debug_file, image_base, sections)
            if command is not None:
                commands.append((module_name, command))
                seen_modules.add(module_name)

        return commands

    for offset, _, module_name in parse_fv_txt(MAIN_FV_TXT, guid_map):
        debug_file = debug_map.get(module_name)
        if debug_file is None:
            continue
        sections = read_section_vmas(debug_file)
        image_base = sec_fv_base + offset + FFS_PE_IMAGE_HEADER_DELTA
        command = build_symbol_command(debug_file, image_base, sections)
        if command is not None:
            commands.append((module_name, command))
            seen_modules.add(module_name)

    for offset, _, module_name in parse_fv_txt(DXE_FV_TXT, guid_map):
        debug_file = debug_map.get(module_name)
        if debug_file is None or module_name in seen_modules:
            continue
        sections = read_section_vmas(debug_file)
        image_base = dxe_fv_base + offset + FFS_PE_IMAGE_HEADER_DELTA
        command = build_symbol_command(debug_file, image_base, sections)
        if command is not None:
            commands.append((module_name, command))
            seen_modules.add(module_name)

    return commands


def emit_commands(sec_fv_base, dxe_fv_base, log_path=None):
    commands = collect_commands(sec_fv_base, dxe_fv_base, log_path)
    print(
        f'Preparing {len(commands)} symbol loads '
        f'(sec_fv_base={hex(sec_fv_base)}, dxe_fv_base={hex(dxe_fv_base)})'
    )
    return commands


if gdb is not None:
    class RiscvUefiLoadSymbols(gdb.Command):
        """Load all RISC-V EDK2 .debug files for the current FV load model.

Usage:
    riscv-uefi-load-symbols
    riscv-uefi-load-symbols 0x80200000
    riscv-uefi-load-symbols --dxe-fv-base 0x80200000 --sec-fv-base 0x80200000
    riscv-uefi-load-symbols --log run_uefi.log
    riscv-uefi-load-symbols --print-only
        """

        def __init__(self):
            super().__init__('riscv-uefi-load-symbols', gdb.COMMAND_USER)

        def invoke(self, arg, from_tty):
            args = gdb.string_to_argv(arg)
            sec_fv_base = DEFAULT_SEC_FV_BASE
            dxe_fv_base = DEFAULT_DXE_FV_BASE
            print_only = False
            log_path = None

            index = 0
            while index < len(args):
                token = args[index]
                if token == '--print-only':
                    print_only = True
                    index += 1
                elif token == '--log':
                    log_path = Path(args[index + 1]).expanduser()
                    index += 2
                elif token == '--sec-fv-base':
                    sec_fv_base = parse_int(args[index + 1])
                    index += 2
                elif token == '--dxe-fv-base':
                    dxe_fv_base = parse_int(args[index + 1])
                    index += 2
                else:
                    dxe_fv_base = parse_int(token)
                    sec_fv_base = dxe_fv_base
                    index += 1

            commands = emit_commands(sec_fv_base, dxe_fv_base, log_path)
            for module_name, command in commands:
                if print_only:
                    print(command)
                    continue

                try:
                    gdb.execute(command, from_tty=False, to_string=True)
                    print(f'Loaded {module_name}')
                except gdb.error as err:
                    print(f'Failed {module_name}: {err}')


    RiscvUefiLoadSymbols()
    print('Loaded riscv_uefi_symbols.py. Use `riscv-uefi-load-symbols [--print-only] [base]`.')
else:
    parser = argparse.ArgumentParser()
    parser.add_argument('base', nargs='?', default=None)
    parser.add_argument('--sec-fv-base', dest='sec_fv_base', default=None)
    parser.add_argument('--dxe-fv-base', dest='dxe_fv_base', default=None)
    parser.add_argument('--log', dest='log_path', default=None)
    args = parser.parse_args()

    dxe_fv_base = parse_int(args.dxe_fv_base or args.base or hex(DEFAULT_DXE_FV_BASE))
    sec_fv_base = parse_int(args.sec_fv_base or args.base or hex(DEFAULT_SEC_FV_BASE))

    log_path = Path(args.log_path).expanduser() if args.log_path else None
    for _, command in emit_commands(sec_fv_base, dxe_fv_base, log_path):
        print(command)