"""
FFBE Memorial master-data datamine — single self-contained pipeline.

Inputs:
  --libgame  path to libgame.so (arm64-v8a)
  --dat-dir  directory containing master-data .dat files (searched recursively)
  --out      output directory (will be created)

Outputs:
  <out>/_manifest.json              manifest extracted from libgame.so
  <out>/_column_dictionary.json     hash -> setter map per table
  <out>/<TABLE>__<basename>.json    decoded, pretty-printed JSON per table

Pipeline:
  1. Parse the master-data manifest from libgame.so .rodata.
  2. For each table: find <basename>.dat, AES-128-CBC decrypt with the
     per-table key, strip PKCS5 padding, parse NDJSON records (separated
     by binary 0x02 0x02 0x0A).
  3. Collect every JSON column hash actually used in records, including
     ones the manifest didn't list.
  4. Build a setter offset table by disassembling every <X>Mst::set*
     leaf symbol in libgame.so.
  5. Scan libgame.so .text for ADRP+ADD references to each column hash
     literal, trace either Pattern A (strcmp+cbz dispatch in
     <X>MstResponse::readParam) or Pattern B (helper+store dispatch in
     <X>MstList::parseObject) to a field offset, and look up the
     matching setter in the owning Mst class.
  6. Rewrite each table's records with `setFoo` -> `foo` field names
     and emit pretty-printed JSON.

Dependencies:  pyelftools, pycryptodome, capstone
"""
from __future__ import annotations

import argparse
import base64
import bisect
import json
import re
import struct
import sys
from collections import defaultdict
from pathlib import Path

from Crypto.Cipher import AES
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from elftools.elf.elffile import ELFFile


# ----------------------------------------------------------------------
# Crypto constants (verified by reversing LapisJNI.decodeCStringForBase64WithNewCrypto)
# ----------------------------------------------------------------------
AES_IV = b"dZMjkk8gFDzKHlsx"

# Regexes
TABLE_RE = re.compile(rb"F_[A-Z0-9_]+")
HASH8_BYTES_RE = re.compile(rb"^[A-Za-z0-9]{8}$")
HASH8_STR_RE = re.compile(r"^[A-Za-z0-9]{8}$")
HAS_DIGIT_RE = re.compile(r"\d")
OFF_HEX_RE = re.compile(r"\[\w+,\s*#0x([0-9a-fA-F]+)\]")
OFF_DEC_RE = re.compile(r"\[\w+,\s*#(\d+)\]")
OFF_NONE_RE = re.compile(r"\[\w+\]")
CBZ_TARGET_RE = re.compile(r"w\d+,\s*#?0?x?([0-9a-fA-F]+)")
JUMP_TARGET_RE = re.compile(r"#?0x([0-9a-fA-F]+)")


def log(*a, **kw):
    print(*a, **kw, flush=True)


# ======================================================================
# 1. Manifest extraction
# ======================================================================
def parse_manifest(blob: bytes):
    """Yield (table, file_basename, aes_key, [col_hashes]) for every manifest entry."""
    pos = 0
    while True:
        m = TABLE_RE.search(blob, pos)
        if not m:
            return
        if blob[m.end():m.end() + 1] != b"\x00":
            pos = m.end()
            continue
        table = m.group(0).decode()
        cursor = m.end() + 1
        tokens = []
        while True:
            nul = blob.find(b"\x00", cursor)
            if nul < 0 or nul == cursor:
                break
            tok = blob[cursor:nul]
            if HASH8_BYTES_RE.match(tok):
                tokens.append(tok.decode())
                cursor = nul + 1
            else:
                break
        if len(tokens) >= 2:
            yield (table, tokens[0], tokens[1], tokens[2:])
        pos = cursor if cursor > pos else m.end()


# ======================================================================
# 2. Decryption
# ======================================================================
def strip_pkcs5(b: bytes) -> bytes:
    if not b:
        return b
    pad = b[-1]
    if 1 <= pad <= 16 and b[-pad:] == bytes([pad]) * pad:
        return b[:-pad]
    return b


def decrypt_dat(dat_path: Path, key8: str) -> bytes:
    key = key8.encode("utf-8")
    key = key + b"\x00" * (16 - len(key))
    out = []
    with dat_path.open("rb") as fh:
        for raw_line in fh:
            line = raw_line.rstrip(b"\r\n")
            if not line:
                out.append(b"")
                continue
            ct = base64.b64decode(line)
            pt = AES.new(key, AES.MODE_CBC, AES_IV).decrypt(ct)
            out.append(strip_pkcs5(pt))
    return b"\n".join(out)


def parse_ndjson(text: str):
    """Records separated by binary control bytes (0x02 0x02 0x0A) between JSON values."""
    dec = json.JSONDecoder()
    records = []
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i] not in "{[":
            i += 1
        if i >= n:
            break
        try:
            obj, j = dec.raw_decode(text, i)
        except json.JSONDecodeError:
            i += 1
            continue
        records.append(obj)
        i = j
    return records


# ======================================================================
# 3. libgame.so introspection (ELF + Capstone)
# ======================================================================
class GameLib:
    def __init__(self, path: Path):
        self.path = path
        self.raw = path.read_bytes()
        self._fh = path.open("rb")
        self.elf = ELFFile(self._fh)
        self.segments = [
            (s["p_vaddr"], s["p_filesz"], s["p_offset"])
            for s in self.elf.iter_segments()
            if s["p_type"] == "PT_LOAD"
        ]
        # symbols: dict name -> (va_start, va_end)
        self.syms_by_name: dict[str, tuple[int, int]] = {}
        for secn in (".dynsym", ".symtab"):
            sec = self.elf.get_section_by_name(secn)
            if sec is None:
                continue
            for s in sec.iter_symbols():
                if not s.name:
                    continue
                v = s["st_value"]
                sz = s["st_size"]
                if v == 0 or sz == 0:
                    continue
                self.syms_by_name.setdefault(s.name, (v, v + sz))
        # sorted symbols for bisect lookup
        self._syms_sorted = sorted(
            (v0, v1, n) for n, (v0, v1) in self.syms_by_name.items()
        )
        self._sym_starts = [s[0] for s in self._syms_sorted]

        text = self.elf.get_section_by_name(".text")
        self.text_va = text["sh_addr"]
        self.text_off = text["sh_offset"]
        self.text_size = text["sh_size"]

        self._md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        self._md.detail = False

    def va_to_off(self, va: int) -> int | None:
        for v, fsz, off in self.segments:
            if v <= va < v + fsz:
                return off + (va - v)
        return None

    def off_to_va(self, off: int) -> int | None:
        for v, fsz, fo in self.segments:
            if fo <= off < fo + fsz:
                return v + (off - fo)
        return None

    def sym_at(self, va: int):
        i = bisect.bisect_right(self._sym_starts, va) - 1
        if i >= 0:
            s = self._syms_sorted[i]
            if s[0] <= va < s[1]:
                return s
        return None

    def disasm_at(self, va: int, size: int):
        off = self.va_to_off(va)
        if off is None:
            return []
        return list(self._md.disasm(self.raw[off:off + size], va))


# ----------------------------------------------------------------------
# Symbol name parsing  (Itanium C++ ABI subset:  _ZN<L><A><L><B><L><C>E…)
# ----------------------------------------------------------------------
def parse_mangled(name: str):
    """Return (scope, method) where scope joins all but the last component."""
    if not name or not name.startswith("_ZN"):
        return (None, None)
    p, comps = 3, []
    while p < len(name):
        if not name[p].isdigit():
            break
        L = 0
        while p < len(name) and name[p].isdigit():
            L = L * 10 + int(name[p])
            p += 1
        if p + L > len(name):
            return (None, None)
        comps.append(name[p:p + L])
        p += L
    if len(comps) >= 2:
        return ("::".join(comps[:-1]), comps[-1])
    if comps:
        return (comps[0], None)
    return (None, None)


def parser_scope_to_mst_class(scope: str | None) -> str | None:
    """`MissionMstResponse` -> `MissionMst`; `TownMstList` -> `TownMst`; etc."""
    if not scope:
        return None
    for suf in ("MstResponse", "MstList"):
        if scope.endswith(suf):
            return scope[: -len(suf)] + "Mst"
    if scope.endswith("Response") and not scope.endswith("MstResponse"):
        return scope[: -len("Response")] + "Mst"
    if scope.endswith("Mst"):
        return scope
    return None


def table_name_to_mst_class(table: str) -> str | None:
    """Derive the expected `<X>Mst` C++ class from the manifest table name.

    `F_UNIT_MST`        -> `UnitMst`
    `F_RB_DEFINE_MST`   -> `RbDefineMst`
    `F_CLSM_CAPTURE_MST`-> `ClsmCaptureMst`
    """
    if not table or not table.startswith("F_"):
        return None
    body = table[2:]
    if body.endswith("_MST"):
        body = body[:-4]
    parts = [p for p in body.split("_") if p]
    if not parts:
        return None
    return "".join(p[:1].upper() + p[1:].lower() for p in parts) + "Mst"


# ----------------------------------------------------------------------
# Setter offset table:  <ClassMst> -> { field_offset: setter_method_name }
# ----------------------------------------------------------------------
# A string-field setter typically starts with `add x0, x0, #FIELD` to compute
# the destination pointer before calling the std::string assign helper.
SETTER_LEADING_ADD_RE = re.compile(
    r"^x0,\s+x0,\s+#(?:0x([0-9a-fA-F]+)|(\d+))$"
)


def extract_first_store_offset(insns, max_ins=30, depth=0, glib=None) -> int | None:
    if depth > 3:
        return None
    for k, ins in enumerate(insns):
        if k >= max_ins:
            break
        m = ins.mnemonic
        if m.startswith("st"):
            mm = OFF_HEX_RE.search(ins.op_str)
            if mm:
                return int(mm.group(1), 16)
            mm = OFF_DEC_RE.search(ins.op_str)
            if mm:
                return int(mm.group(1))
            if OFF_NONE_RE.search(ins.op_str):
                return 0
        # First instruction of a string-field setter:  add x0, x0, #FIELD
        if m == "add" and k == 0:
            mm = SETTER_LEADING_ADD_RE.match(ins.op_str.strip())
            if mm:
                return int(mm.group(1), 16) if mm.group(1) else int(mm.group(2))
        if m == "ret":
            break
        if m == "b" and glib is not None:
            mm = JUMP_TARGET_RE.match(ins.op_str.strip())
            if mm:
                tgt = int(mm.group(1), 16)
                return extract_first_store_offset(
                    glib.disasm_at(tgt, 96), max_ins, depth + 1, glib
                )
            break
    return None


SETTER_METHOD_RE = re.compile(r"^set[A-Z0-9]")


# `add x0, x?, #<imm>` -- field-pointer computation used by inlined string
# assignments (e.g. `*(string*)(this+FIELD) = parsed_value`).
FIELD_PTR_ADD_RE = re.compile(
    r"^x0,\s+x(\d+),\s+#(?:0x([0-9a-fA-F]+)|(\d+))$"
)


def _scan_handler_for_target(
    insns,
    owning_cls: str | None,
    setter_table: dict[str, dict[int, str]],
    va_to_setter: dict[int, tuple[str, str, int]],
    max_ins: int = 40,
) -> tuple[int, str | None, str | None] | None:
    """Scan a handler block; return (offset, setter_name, mst_class) or None.

    Detects three shapes:
      * inline `st*  w?, [xT, #FIELD]`
      * `bl <setter>` where the call target is a known `<Cls>Mst::set*` symbol
        (the setter's own offset is read from `setter_table`).
      * `add x0, xT, #FIELD` -- field-pointer compute, used by inlined string
        copies. `FIELD` is accepted only when `setter_table[owning_cls]` has
        an entry at that offset (so we never invent offsets out of thin air).
    """
    for k, ins in enumerate(insns):
        if k >= max_ins:
            break
        m = ins.mnemonic
        # Stop at handler boundary: unconditional branch to a sibling block.
        # `b.eq`/`b.ne`/etc. (mnemonic starts with `b.`) are NOT terminators.
        if m == "b":
            break
        if m == "ret":
            break
        if m.startswith("st"):
            off = None
            mm = OFF_HEX_RE.search(ins.op_str)
            if mm:
                off = int(mm.group(1), 16)
            else:
                mm = OFF_DEC_RE.search(ins.op_str)
                if mm:
                    off = int(mm.group(1))
                elif OFF_NONE_RE.search(ins.op_str):
                    off = 0
            if off is not None:
                if owning_cls:
                    name = setter_table.get(owning_cls, {}).get(off)
                    return (off, name, owning_cls)
                return (off, None, None)
        elif m == "bl":
            mm = JUMP_TARGET_RE.match(ins.op_str.strip())
            if mm:
                tgt = int(mm.group(1), 16)
                hit = va_to_setter.get(tgt)
                if hit is not None:
                    cls, meth, off = hit
                    if owning_cls and cls != owning_cls:
                        continue
                    return (off, meth, cls)
            # non-setter `bl` (string ctor, atoi, strdup) -> keep scanning
            continue
        elif m == "add" and owning_cls:
            mm = FIELD_PTR_ADD_RE.match(ins.op_str.strip())
            if mm:
                base_reg = int(mm.group(1))
                # Skip add involving x29 (frame ptr) or sp (already caught
                # by the regex shape requiring `x<N>`, but x29 == 29).
                if base_reg == 29:
                    continue
                off = int(mm.group(2), 16) if mm.group(2) else int(mm.group(3))
                name = setter_table.get(owning_cls, {}).get(off)
                if name is not None:
                    return (off, name, owning_cls)
                # No matching setter at this offset -> don't accept; keep
                # scanning in case a real store/bl appears.
                continue
    return None


def build_setter_table(
    glib: GameLib,
) -> tuple[dict[str, dict[int, str]], dict[int, tuple[str, str, int]]]:
    """Returns (setter_table, va_to_setter).

    setter_table: `{class: {offset: setter_method}}`
    va_to_setter: `{symbol_start_va: (class, setter_method, offset)}`
    """
    log("  scanning setter symbols ...")
    out: dict[str, dict[int, str]] = defaultdict(dict)
    va_to_setter: dict[int, tuple[str, str, int]] = {}
    for v_start, v_end, name in glib._syms_sorted:
        cls, method = parse_mangled(name)
        if not cls or not method:
            continue
        if not cls.endswith("Mst"):
            continue
        if not SETTER_METHOD_RE.match(method):
            continue
        size = min(v_end - v_start, 128)
        off = extract_first_store_offset(glib.disasm_at(v_start, size), glib=glib)
        if off is None:
            continue
        out[cls].setdefault(off, method)
        va_to_setter[v_start] = (cls, method, off)
    log(f"  setter table: {len(out)} Mst classes, "
        f"{sum(len(v) for v in out.values())} offsets, "
        f"{len(va_to_setter)} setter VAs")
    return dict(out), va_to_setter


# ----------------------------------------------------------------------
# ADRP+ADD xref scan for hash literals
# ----------------------------------------------------------------------
def find_string_va(glib: GameLib, s: str) -> list[int]:
    """Find all VAs where the NUL-terminated string `s` exists in libgame.so."""
    needle = b"\x00" + s.encode("ascii") + b"\x00"
    raw = glib.raw
    out, p = [], 0
    while True:
        i = raw.find(needle, p)
        if i < 0:
            break
        va = glib.off_to_va(i + 1)
        if va is not None:
            out.append(va)
        p = i + 1
    return out


def find_addr_xrefs(glib: GameLib, target_vas: set[int]) -> dict[int, list[tuple[int, int]]]:
    """Scan .text for ADRP+ADD sequences and record (adrp_pc, add_pc) per target VA.

    For each register we keep the last (page, adrp_pc) we saw; when a subsequent
    ADD imm uses that register as Rn, we compute the literal target and check
    membership in `target_vas`.
    """
    text = glib.raw[glib.text_off:glib.text_off + glib.text_size]
    text_va = glib.text_va
    n_ins = glib.text_size // 4
    xrefs: dict[int, list[tuple[int, int]]] = defaultdict(list)
    adrp_state: dict[int, tuple[int, int]] = {}
    for i in range(n_ins):
        pc = text_va + 4 * i
        word = struct.unpack_from("<I", text, 4 * i)[0]
        # ADRP: bits[31]=1, bits[28:24]=10000 ; mask = 0x9F000000, value = 0x90000000
        if (word & 0x9F000000) == 0x90000000:
            immlo = (word >> 29) & 0x3
            immhi = (word >> 5) & 0x7FFFF
            imm = (immhi << 2) | immlo
            if imm & (1 << 20):
                imm -= 1 << 21
            page_base = (pc & ~0xFFF) + (imm << 12)
            Rd = word & 0x1F
            adrp_state[Rd] = (page_base, pc)
        # ADD (imm, 64-bit, shift=0): bits[31:23] = 10010001 0 ; mask 0xFF800000 = 0x91000000
        elif (word & 0xFF800000) == 0x91000000:
            imm12 = (word >> 10) & 0xFFF
            Rn = (word >> 5) & 0x1F
            if Rn in adrp_state:
                page_base, adrp_pc = adrp_state[Rn]
                target = page_base + imm12
                if target in target_vas:
                    xrefs[target].append((adrp_pc, pc))
    return dict(xrefs)


# ----------------------------------------------------------------------
# Dispatch tracers
# ----------------------------------------------------------------------
def trace_pattern_A(
    glib: GameLib,
    add_pc: int,
    owning_cls: str | None,
    setter_table: dict[str, dict[int, str]],
    va_to_setter: dict[int, tuple[str, str, int]],
    window: int = 22,
) -> tuple[int, str | None, str | None] | None:
    """`<X>MstResponse::readParam` shape:
        ADRP+ADD x1,#hash ; mov x0,key ; bl strcmp ; cbz w0, handler
        handler: ... str w?, [xT, #FIELD]   OR   ... bl <Class>Mst::setXxx
    Returns (offset, setter_name|None, owning_class|None).
    """
    insns = glib.disasm_at(add_pc, (window + 2) * 4)
    for k, ins in enumerate(insns):
        if k == 0:
            continue
        m = ins.mnemonic
        if m == "cbz":
            mm = CBZ_TARGET_RE.search(ins.op_str)
            if mm:
                handler = int(mm.group(1), 16)
                return _scan_handler_for_target(
                    glib.disasm_at(handler, 200),
                    owning_cls, setter_table, va_to_setter,
                )
        elif m == "cbnz":
            return _scan_handler_for_target(
                glib.disasm_at(ins.address + 4, 200),
                owning_cls, setter_table, va_to_setter,
            )
        elif m == "ret":
            break
    return None


def trace_pattern_B(
    glib: GameLib,
    add_pc: int,
    owning_cls: str | None,
    setter_table: dict[str, dict[int, str]],
    va_to_setter: dict[int, tuple[str, str, int]],
    window: int = 14,
) -> tuple[int, str | None, str | None] | None:
    """`<X>MstList::parseObject` shape:
        ADRP+ADD x1,#hash ; mov... ; bl helper ; <store or bl setter>
    No cbz/cbnz; the helper does the map lookup using the hash as the key.
    """
    insns = glib.disasm_at(add_pc, (window + 8) * 4)
    if len(insns) < 3:
        return None
    saw_bl = False
    for k, ins in enumerate(insns):
        if k == 0:
            continue
        m = ins.mnemonic
        if not saw_bl:
            if m == "bl":
                saw_bl = True
                continue
            if m in ("ret", "cbz", "cbnz", "b"):
                return None  # not pattern B
        else:
            if m.startswith("st"):
                off = None
                mm = OFF_HEX_RE.search(ins.op_str)
                if mm:
                    off = int(mm.group(1), 16)
                else:
                    mm = OFF_DEC_RE.search(ins.op_str)
                    if mm:
                        off = int(mm.group(1))
                    elif OFF_NONE_RE.search(ins.op_str):
                        off = 0
                if off is not None:
                    name = (
                        setter_table.get(owning_cls, {}).get(off)
                        if owning_cls else None
                    )
                    return (off, name, owning_cls)
            if m == "bl":
                mm = JUMP_TARGET_RE.match(ins.op_str.strip())
                if mm:
                    tgt = int(mm.group(1), 16)
                    hit = va_to_setter.get(tgt)
                    if hit is not None:
                        cls, meth, off = hit
                        if owning_cls and cls != owning_cls:
                            continue
                        return (off, meth, cls)
                continue
            if m == "adrp" or m == "ret":
                return None
            if k > 12:
                return None
    return None


def resolve_hashes(
    glib: GameLib,
    hashes: set[str],
    setter_table: dict[str, dict[int, str]],
    va_to_setter: dict[int, tuple[str, str, int]],
) -> dict[str, list[dict]]:
    """Return {hash: [candidate, ...]} (one entry per Mst class that uses the hash).

    A candidate is `{mst_class, setter, offset, scope, confidence, evidence_pc}`.
    The same hash often appears in several parsers (e.g. `setSpResist` exists on
    `UnitMst`, `EquipItemMst`, `VisionCardMst`, `MonsterPartsMst` at different
    field offsets); the caller picks the right one per table.
    """
    log(f"  locating {len(hashes)} hash literals in .rodata ...")
    hash_to_target_vas: dict[str, list[int]] = {}
    for h in hashes:
        vas = find_string_va(glib, h)
        if vas:
            hash_to_target_vas[h] = vas
    log(f"  hashes found in .rodata: {len(hash_to_target_vas)}/{len(hashes)}")

    target_set: set[int] = set()
    for vas in hash_to_target_vas.values():
        target_set.update(vas)

    log(f"  scanning .text for ADRP+ADD xrefs ({glib.text_size // 4} insns) ...")
    xrefs = find_addr_xrefs(glib, target_set)
    log(f"  target VAs with at least one xref: {len(xrefs)}/{len(target_set)}")

    PRIMARY_SUFFIXES = ("MstResponse", "MstList", "Response")
    resolved: dict[str, list[dict]] = {}
    for h, vas in hash_to_target_vas.items():
        add_pcs: list[int] = []
        for va in vas:
            for (_adrp_pc, add_pc) in xrefs.get(va, []):
                add_pcs.append(add_pc)
        if not add_pcs:
            continue
        # key: (mst_class, offset) -- collapse duplicates from the same parser
        per_class: dict[tuple[str, int], dict] = {}
        for pc in add_pcs:
            s = glib.sym_at(pc)
            if not s:
                continue
            scope, _meth = parse_mangled(s[2])
            owning_cls = parser_scope_to_mst_class(scope)
            if not owning_cls:
                continue
            is_primary = scope and any(scope.endswith(suf) for suf in PRIMARY_SUFFIXES)
            trace = trace_pattern_A(
                glib, pc, owning_cls, setter_table, va_to_setter
            )
            if trace is None:
                trace = trace_pattern_B(
                    glib, pc, owning_cls, setter_table, va_to_setter
                )
            if trace is None:
                continue
            store_off, setter, found_cls = trace
            cls_for_lookup = found_cls or owning_cls
            if not setter:
                setter = setter_table.get(cls_for_lookup, {}).get(store_off)
            if not setter:
                continue
            cand = {
                "mst_class": cls_for_lookup,
                "setter": setter,
                "offset": store_off,
                "scope": scope,
                "confidence": "primary" if is_primary else "secondary",
                "evidence_pc": hex(pc),
            }
            key = (cls_for_lookup, store_off)
            existing = per_class.get(key)
            if existing is None or (
                existing["confidence"] != "primary" and is_primary
            ):
                per_class[key] = cand
        if per_class:
            resolved[h] = list(per_class.values())
    n_total_candidates = sum(len(v) for v in resolved.values())
    log(f"  resolved hashes: {len(resolved)}/{len(hashes)} "
        f"({n_total_candidates} class-distinct candidates)")
    return resolved


# ======================================================================
# 4. Rename + emit
# ======================================================================
def setter_to_field(name: str) -> str:
    if not name or not name.startswith("set") or len(name) < 4:
        return name
    return name[3].lower() + name[4:]


def rename_keys(obj, mapping: dict[str, str]):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            new_k = mapping.get(k, k)
            if new_k in out:
                new_k = f"{new_k}__{k}"
            out[new_k] = rename_keys(v, mapping)
        return out
    if isinstance(obj, list):
        return [rename_keys(x, mapping) for x in obj]
    return obj


# ======================================================================
# CLI / main
# ======================================================================
def index_dat_files(dat_root: Path) -> dict[str, Path]:
    out: dict[str, Path] = {}
    for p in dat_root.rglob("*.dat"):
        out.setdefault(p.stem, p)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="FFBE Memorial master-data datamine pipeline (single script)."
    )
    ap.add_argument("--libgame", required=True, type=Path,
                    help="Path to libgame.so (arm64-v8a build).")
    ap.add_argument("--dat-dir", required=True, type=Path,
                    help="Directory containing master-data .dat files "
                         "(searched recursively).")
    ap.add_argument("--out", required=True, type=Path,
                    help="Output directory for decoded JSON files.")
    args = ap.parse_args(argv)

    if not args.libgame.is_file():
        ap.error(f"libgame not found: {args.libgame}")
    if not args.dat_dir.is_dir():
        ap.error(f"dat directory not found: {args.dat_dir}")
    args.out.mkdir(parents=True, exist_ok=True)

    # --- Step 1: parse manifest ---
    log("[1/6] Loading libgame.so ...")
    glib = GameLib(args.libgame)
    log(f"  {glib.path.name}: {len(glib.raw):,} bytes; "
        f"{len(glib.syms_by_name):,} symbols")

    log("[2/6] Parsing master-data manifest ...")
    manifest = list(parse_manifest(glib.raw))
    log(f"  manifest entries: {len(manifest)}")
    (args.out / "_manifest.json").write_text(
        json.dumps(
            [{"table": t, "file": f, "aes_key": k, "columns": c}
             for (t, f, k, c) in manifest],
            indent=2, ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    # --- Step 2: locate .dat files ---
    log("[3/6] Indexing .dat files ...")
    dat_index = index_dat_files(args.dat_dir)
    log(f"  found {len(dat_index)} .dat files under {args.dat_dir}")
    matched = [(t, f, k, c) for (t, f, k, c) in manifest if f in dat_index]
    log(f"  manifest entries with matching .dat: {len(matched)}")

    # --- Step 3: decrypt all .dat files & parse records ---
    log("[4/6] Decrypting + parsing all matched .dat files ...")
    decrypted: dict[str, dict] = {}   # table -> {file, key, columns_in_records}
    decrypt_failures = 0
    for (table, fname, key, manifest_cols) in matched:
        dat_path = dat_index[fname]
        try:
            plain = decrypt_dat(dat_path, key)
            records = parse_ndjson(plain.decode("utf-8"))
        except Exception as e:
            log(f"  ERR  {table:40s} {fname}.dat  {e!r}")
            decrypt_failures += 1
            continue
        # union of keys appearing in records
        seen_keys: set[str] = set()
        for r in records:
            if isinstance(r, dict):
                seen_keys.update(r.keys())
        decrypted[table] = {
            "file": fname,
            "key": key,
            "manifest_cols": manifest_cols,
            "records": records,
            "keys_in_records": seen_keys,
        }
    log(f"  decrypted: {len(decrypted)}  failures: {decrypt_failures}")

    # --- Step 4: collect every hash to resolve ---
    all_hashes: set[str] = set()
    for table, info in decrypted.items():
        all_hashes.update(info["manifest_cols"])
        all_hashes.update(
            k for k in info["keys_in_records"]
            if HASH8_STR_RE.match(k) and HAS_DIGIT_RE.search(k)
        )
    log(f"  unique candidate hashes across all tables: {len(all_hashes)}")

    # --- Step 5: resolve hashes via setter+dispatch analysis ---
    log("[5/6] Building setter offset table & tracing dispatch ...")
    setter_table, va_to_setter = build_setter_table(glib)
    hash_resolutions = resolve_hashes(
        glib, all_hashes, setter_table, va_to_setter
    )

    # Build per-table column dictionary: for each table pick the candidate
    # whose `mst_class` matches the table's expected owning class.
    col_dict: dict[str, dict[str, dict]] = {}
    for table, info in decrypted.items():
        want_cls = table_name_to_mst_class(table)
        tdict: dict[str, dict] = {}
        for h in sorted(set(info["manifest_cols"]) | info["keys_in_records"]):
            cands = hash_resolutions.get(h)
            if not cands:
                continue
            chosen = None
            # 1) exact match on owning class
            if want_cls:
                chosen = next(
                    (c for c in cands if c["mst_class"] == want_cls), None
                )
            # 2) fall back to a `primary` (MstResponse/MstList/Response) candidate
            if chosen is None:
                chosen = next(
                    (c for c in cands if c["confidence"] == "primary"), None
                )
            # 3) last resort: any candidate (only useful when ambiguous)
            if chosen is None and len(cands) == 1:
                chosen = cands[0]
            if chosen is not None:
                tdict[h] = chosen
        col_dict[table] = tdict
    (args.out / "_column_dictionary.json").write_text(
        json.dumps(col_dict, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    log(f"  column dict written ({sum(len(v) for v in col_dict.values())} entries)")

    # --- Step 6: rename & emit pretty JSON per table ---
    log("[6/6] Renaming columns and writing decoded JSON ...")
    total_resolved_cols = 0
    total_unresolved_cols = 0
    files_clean = 0
    for table, info in decrypted.items():
        mapping = {
            h: setter_to_field(r["setter"])
            for h, r in col_dict[table].items()
            if r.get("setter")
        }
        decoded_records = [rename_keys(r, mapping) for r in info["records"]]
        # Count still-hash keys after renaming
        union_keys: set[str] = set()
        for r in decoded_records:
            if isinstance(r, dict):
                union_keys.update(r.keys())
        unresolved = {
            k for k in union_keys
            if HASH8_STR_RE.match(k) and HAS_DIGIT_RE.search(k)
        }
        if not unresolved:
            files_clean += 1
        total_resolved_cols += len(mapping)
        total_unresolved_cols += len(unresolved)

        out_path = args.out / f"{table}__{info['file']}.json"
        out_path.write_text(
            json.dumps(
                {
                    "table": table,
                    "file_basename": info["file"],
                    "renamed_keys": mapping,
                    "unresolved_hash_keys": sorted(unresolved),
                    "records": decoded_records,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

    log(f"\nDone.")
    log(f"  files written:        {len(decrypted)}")
    log(f"  fully clean files:    {files_clean}/{len(decrypted)}")
    log(f"  resolved columns:     {total_resolved_cols}")
    log(f"  unresolved columns:   {total_unresolved_cols}")
    log(f"  output directory:     {args.out}")


if __name__ == "__main__":
    main()
