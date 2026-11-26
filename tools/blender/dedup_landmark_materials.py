#!/usr/bin/env python3
"""Deduplicate procedural 512x512 landmark PBR textures into shared BC7 assets.

Exports the 10 unique 512x512 procedural PBR texture triplets (30 PNGs total,
since `mat_landmark_paint` reuses `timber`'s triplet) and 11 shared Godot
`StandardMaterial3D` `.tres` materials into `assets/generated/landmarks/shared/`,
strips duplicate embedded PNG images from every `assets/generated/landmarks/*.glb`
while preserving 100% of mesh geometry (`POSITION`, `NORMAL`, `TANGENT`,
`TEXCOORD_0`, `TEXCOORD_1`, `COLOR_0`), `col_*` colliders, `Lantern_*` empties,
and untextured emissive/collision materials, updates every `*.glb.import` to
bind external shared `.tres` materials with `gltf/embedded_image_handling=2`,
BC7-compresses `shared/*.png.import` via `tools/textures/optimize_imports.py`,
and removes redundant per-GLB `*_lm_*.png{,.import}` files.

Idempotent & repeatable — runnable either via Blender OR standalone Python:
    blender --background --python tools/blender/dedup_landmark_materials.py
    python3 tools/blender/dedup_landmark_materials.py
    python3 tools/blender/dedup_landmark_materials.py --godot-import
"""

import argparse
import glob
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import types
import zlib

import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
TEXTURES_TOOL_DIR = os.path.join(REPO_ROOT, "tools", "textures")

SHARED_RES_PREFIX = "res://assets/generated/landmarks/shared/"
TEXTURE_SIZE = 512

# Exact shared textured material definitions matching `_landmark_common.py`
# `MAT_NAMES` & `make_materials()` (lines 846-940) and Godot's native glTF import:
# - When a roughness texture is connected in Blender Principled BSDF, glTF sets
#   `roughnessFactor = 1.0` so `roughness = 1.0` multiplies `lm_*_rough.png` (G channel).
# - glTF 2.0 `COLOR_0` vertex colors are already linear (converted via `srgb()` in
#   `_landmark_common.py`), so `vertex_color_is_srgb = false` matches native glTF import
#   and prevents double-gamma darkening.
# - Untextured materials (`mat_landmark_glass`, `mat_landmark_skull_glow`,
#   `mat_collision`) are intentionally omitted so they remain untouched inside each GLB.
SHARED_MATERIALS = {
    "mat_landmark_limestone": {
        "tex_key": "limestone",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 1.0,
        "cull_mode": 0,
    },
    "mat_landmark_limestone_moss": {
        "tex_key": "limestone_moss",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 1.0,
        "cull_mode": 0,
    },
    "mat_landmark_basalt": {
        "tex_key": "basalt",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 1.1,
        "cull_mode": 0,
    },
    "mat_landmark_temple_stone": {
        "tex_key": "temple_stone",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 1.05,
        "cull_mode": 0,
    },
    "mat_landmark_skull_stone": {
        "tex_key": "skull_stone",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 1.05,
        "cull_mode": 0,
    },
    "mat_landmark_timber": {
        "tex_key": "timber",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 0.95,
        "cull_mode": 0,
    },
    "mat_landmark_paint": {
        "tex_key": "timber",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 0.65,
        "cull_mode": 0,
    },
    "mat_landmark_rope": {
        "tex_key": "rope",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 0.85,
        "cull_mode": 0,
    },
    "mat_landmark_iron": {
        "tex_key": "iron",
        "metallic": 0.68,
        "roughness": 1.0,
        "normal_scale": 0.85,
        "cull_mode": 0,
    },
    "mat_landmark_brass": {
        "tex_key": "brass",
        "metallic": 0.86,
        "roughness": 1.0,
        "normal_scale": 0.65,
        "cull_mode": 0,
    },
    "mat_foliage": {
        "tex_key": "foliage",
        "metallic": 0.0,
        "roughness": 1.0,
        "normal_scale": 0.65,
        "cull_mode": 2,
    },
}

PBR_SET_ORDER = (
    "limestone",
    "limestone_moss",
    "basalt",
    "temple_stone",
    "skull_stone",
    "timber",
    "rope",
    "iron",
    "brass",
    "foliage",
)

GLB_MAGIC = b"glTF"
GLB_VERSION = 2
CHUNK_JSON = b"JSON"
CHUNK_BIN = b"BIN\x00"


def _import_landmark_common():
    """Import `_landmark_common` cleanly under both Blender and standalone Python."""
    if SCRIPT_DIR not in sys.path:
        sys.path.insert(0, SCRIPT_DIR)

    if "_landmark_common" in sys.modules:
        return sys.modules["_landmark_common"]

    # When running outside Blender, stub `bpy`, `bmesh`, and `mathutils` solely
    # so `_landmark_common`'s pure-NumPy `synth_*_pbr` functions can be imported
    # without duplicating synthesis code.
    added_stubs = []
    try:
        import bpy  # noqa: F401
    except ImportError:
        for mod_name in ("bpy", "bmesh"):
            if mod_name not in sys.modules:
                sys.modules[mod_name] = types.ModuleType(mod_name)
                added_stubs.append(mod_name)
        if "mathutils" not in sys.modules:
            mu = types.ModuleType("mathutils")

            class _StubMatrix:
                @staticmethod
                def Rotation(*_args, **_kwargs):
                    return None

                @staticmethod
                def Translation(*_args, **_kwargs):
                    return None

                @staticmethod
                def Diagonal(*_args, **_kwargs):
                    return None

            class _StubVector:
                def __init__(self, *_args, **_kwargs):
                    pass

            mu.Matrix = _StubMatrix
            mu.Vector = _StubVector
            sys.modules["mathutils"] = mu
            added_stubs.append("mathutils")

    import _landmark_common as lc

    return lc


def _encode_rgb_png(rgb_u8: np.ndarray) -> bytes:
    """Encode an (H, W, 3) uint8 array as a deterministic 8-bit RGB PNG."""
    assert rgb_u8.ndim == 3 and rgb_u8.shape[2] == 3 and rgb_u8.dtype == np.uint8
    h, w, _ = rgb_u8.shape
    # Prepend filter type 0 (None) to each scanline
    raw = np.empty((h, w * 3 + 1), dtype=np.uint8)
    raw[:, 0] = 0
    raw[:, 1:] = rgb_u8.reshape(h, w * 3)
    compressed = zlib.compress(raw.tobytes(), level=9)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag)
        crc = zlib.crc32(payload, crc) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)  # 8-bit RGB
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )


def _array_to_png_bytes(arr: np.ndarray) -> bytes:
    """Convert float [0..1] array (H, W) or (H, W, 3) to Blender-oriented RGB PNG bytes.

    Blender stores `bpy.data.images` pixels bottom-to-top (row 0 = V=0) and flips
    vertically when writing PNGs, so we apply `np.flipud` to match UV/normal orientation
    of the exported landmark GLBs identically.
    """
    flipped = np.flipud(np.clip(arr, 0.0, 1.0))
    if flipped.ndim == 2:
        u8 = np.round(flipped * 255.0).astype(np.uint8)
        rgb = np.stack([u8, u8, u8], axis=-1)
    else:
        rgb = np.round(flipped[..., :3] * 255.0).astype(np.uint8)
    return _encode_rgb_png(rgb)


def _write_if_changed_bytes(path: str, data: bytes) -> bool:
    if os.path.isfile(path):
        with open(path, "rb") as fh:
            if fh.read() == data:
                return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, path)
    return True


def _write_if_changed_text(path: str, text: str) -> bool:
    data = text.encode("utf-8")
    return _write_if_changed_bytes(path, data)


def export_shared_textures(shared_dir: str) -> tuple[int, int]:
    """Export all 30 shared 512x512 PBR PNGs into `shared_dir`.

    Returns `(total_pngs, written_pngs)`.
    """
    lc = _import_landmark_common()
    rs = np.random.RandomState(lc.SEED)

    # Call synthesis functions in the exact same RNG order as `_landmark_common.make_materials()`!
    pbr_sets = {
        "limestone": lc.synth_limestone_pbr(rs, TEXTURE_SIZE, mossy=False, bone_carved=False),
        "limestone_moss": lc.synth_limestone_pbr(rs, TEXTURE_SIZE, mossy=True, bone_carved=False),
        "basalt": lc.synth_basalt_pbr(rs, TEXTURE_SIZE),
        "temple_stone": lc.synth_temple_stone_pbr(rs, TEXTURE_SIZE),
        "skull_stone": lc.synth_limestone_pbr(rs, TEXTURE_SIZE, mossy=False, bone_carved=True),
        "timber": lc.synth_timber_pbr(rs, TEXTURE_SIZE),
        "rope": lc.synth_rope_pbr(rs, TEXTURE_SIZE),
        "iron": lc.synth_metal_pbr(rs, TEXTURE_SIZE, rusty=True),
        "brass": lc.synth_metal_pbr(rs, TEXTURE_SIZE, rusty=False),
        "foliage": lc.synth_foliage_pbr(rs, TEXTURE_SIZE),
    }

    os.makedirs(shared_dir, exist_ok=True)
    total = 0
    written = 0
    for key in PBR_SET_ORDER:
        alb_arr, nrm_arr, rgh_arr = pbr_sets[key]
        for suffix, arr in (("albedo", alb_arr), ("normal", nrm_arr), ("rough", rgh_arr)):
            out_path = os.path.join(shared_dir, f"lm_{key}_{suffix}.png")
            png_bytes = _array_to_png_bytes(arr)
            if _write_if_changed_bytes(out_path, png_bytes):
                written += 1
            total += 1
    return total, written


def _format_float(val: float) -> str:
    s = f"{val:.6f}".rstrip("0").rstrip(".")
    return s if "." in s else s + ".0"


def export_shared_materials(shared_dir: str) -> tuple[int, int]:
    """Generate the 11 shared Godot `StandardMaterial3D` `.tres` files."""
    os.makedirs(shared_dir, exist_ok=True)
    total = 0
    written = 0
    for mat_name, cfg in SHARED_MATERIALS.items():
        tex_key = cfg["tex_key"]
        alb_res = f"{SHARED_RES_PREFIX}lm_{tex_key}_albedo.png"
        rgh_res = f"{SHARED_RES_PREFIX}lm_{tex_key}_rough.png"
        nrm_res = f"{SHARED_RES_PREFIX}lm_{tex_key}_normal.png"

        lines = [
            '[gd_resource type="StandardMaterial3D" load_steps=4 format=3]',
            "",
            f'[ext_resource type="Texture2D" path="{alb_res}" id="1"]',
            f'[ext_resource type="Texture2D" path="{rgh_res}" id="2"]',
            f'[ext_resource type="Texture2D" path="{nrm_res}" id="3"]',
            "",
            "[resource]",
            f'resource_name = "{mat_name}"',
        ]
        if cfg["cull_mode"] != 0:
            lines.append(f'cull_mode = {cfg["cull_mode"]}')
        lines.extend(
            [
                "vertex_color_use_as_albedo = true",
                'albedo_texture = ExtResource("1")',
            ]
        )
        if cfg["metallic"] != 0.0:
            lines.append(f'metallic = {_format_float(cfg["metallic"])}')
        lines.extend(
            [
                f'roughness = {_format_float(cfg["roughness"])}',
                'roughness_texture = ExtResource("2")',
                "roughness_texture_channel = 1",
                "normal_enabled = true",
                f'normal_scale = {_format_float(cfg["normal_scale"])}',
                'normal_texture = ExtResource("3")',
                "",
            ]
        )

        out_path = os.path.join(shared_dir, f"{mat_name}.tres")
        if _write_if_changed_text(out_path, "\n".join(lines)):
            written += 1
        total += 1
    return total, written


def _parse_glb(data: bytes) -> tuple[dict, bytes]:
    if len(data) < 20:
        raise ValueError("GLB file too small")
    magic, version, total_len = struct.unpack_from("<4sII", data, 0)
    if magic != GLB_MAGIC or version != GLB_VERSION:
        raise ValueError(f"Invalid GLB header: magic={magic!r} version={version}")
    if total_len != len(data):
        raise ValueError(f"GLB length mismatch: header={total_len} actual={len(data)}")

    offset = 12
    gltf_json = None
    bin_chunk = b""
    while offset < total_len:
        if offset + 8 > total_len:
            raise ValueError("Truncated GLB chunk header")
        clen, ctype = struct.unpack_from("<I4s", data, offset)
        offset += 8
        if offset + clen > total_len:
            raise ValueError("Truncated GLB chunk body")
        payload = data[offset : offset + clen]
        offset += clen
        if ctype == CHUNK_JSON:
            gltf_json = json.loads(payload.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            bin_chunk = payload

    if gltf_json is None:
        raise ValueError("GLB missing JSON chunk")
    return gltf_json, bin_chunk


def _pack_glb(gltf_json: dict, bin_bytes: bytes) -> bytes:
    json_raw = json.dumps(gltf_json, separators=(",", ":")).encode("utf-8")
    json_pad = (-len(json_raw)) % 4
    if json_pad:
        json_raw += b" " * json_pad

    bin_pad = (-len(bin_bytes)) % 4
    if bin_pad:
        bin_bytes = bin_bytes + (b"\x00" * bin_pad)

    chunks = [struct.pack("<I4s", len(json_raw), CHUNK_JSON), json_raw]
    if bin_bytes:
        chunks.extend([struct.pack("<I4s", len(bin_bytes), CHUNK_BIN), bin_bytes])

    total_len = 12 + sum(len(c) for c in chunks)
    header = struct.pack("<4sII", GLB_MAGIC, GLB_VERSION, total_len)
    return header + b"".join(chunks)


def _collect_primitive_signatures(gltf_json: dict) -> list[tuple[str, tuple[str, ...]]]:
    sigs = []
    for mesh in gltf_json.get("meshes", []):
        mname = mesh.get("name", "")
        for prim in mesh.get("primitives", []):
            attrs = tuple(sorted(prim.get("attributes", {}).keys()))
            sigs.append((mname, attrs))
    return sigs


def _collect_material_tex_refs(mat: dict) -> list[dict]:
    """Return every textureInfo dict referenced inside a glTF material."""
    refs = []
    for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
        if isinstance(mat.get(key), dict) and "index" in mat[key]:
            refs.append(mat[key])
    pbr = mat.get("pbrMetallicRoughness")
    if isinstance(pbr, dict):
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            if isinstance(pbr.get(key), dict) and "index" in pbr[key]:
                refs.append(pbr[key])
    return refs


def _validate_glb(glb_bytes: bytes, expected_sigs: list[tuple[str, tuple[str, ...]]]) -> None:
    gltf, bin_bytes = _parse_glb(glb_bytes)
    actual_sigs = _collect_primitive_signatures(gltf)
    if actual_sigs != expected_sigs:
        raise ValueError(
            f"Primitive attributes changed after stripping: {actual_sigs} != {expected_sigs}"
        )

    buffers = gltf.get("buffers", [])
    buf_len = buffers[0]["byteLength"] if buffers else 0
    if buf_len > len(bin_bytes):
        raise ValueError(f"buffer.byteLength ({buf_len}) exceeds BIN chunk ({len(bin_bytes)})")

    bvs = gltf.get("bufferViews", [])
    for idx, bv in enumerate(bvs):
        off = bv.get("byteOffset", 0)
        blen = bv["byteLength"]
        if off < 0 or blen < 0 or off + blen > buf_len:
            raise ValueError(f"bufferView[{idx}] out of bounds: {off}+{blen} > {buf_len}")

    for idx, acc in enumerate(gltf.get("accessors", [])):
        if "bufferView" in acc:
            bvi = acc["bufferView"]
            if bvi < 0 or bvi >= len(bvs):
                raise ValueError(f"accessor[{idx}] invalid bufferView {bvi}")
        sparse = acc.get("sparse")
        if sparse:
            for part in ("indices", "values"):
                bvi = sparse[part]["bufferView"]
                if bvi < 0 or bvi >= len(bvs):
                    raise ValueError(f"accessor[{idx}].sparse.{part} invalid bufferView {bvi}")


def strip_glb_embedded_images(glb_path: str) -> tuple[list[str], bool, int, int]:
    """Strip shared-material embedded PNGs from a `.glb` and compact its BIN chunk.

    Returns `(shared_mat_names_present, modified, bytes_before, bytes_after)`.
    """
    with open(glb_path, "rb") as fh:
        raw = fh.read()
    bytes_before = len(raw)

    gltf, bin_bytes = _parse_glb(raw)
    orig_sigs = _collect_primitive_signatures(gltf)

    present_shared_mats: list[str] = []
    removed_any_tex_ref = False

    for mat in gltf.get("materials", []):
        name = mat.get("name", "")
        if name in SHARED_MATERIALS:
            if name not in present_shared_mats:
                present_shared_mats.append(name)
            for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
                if key in mat:
                    del mat[key]
                    removed_any_tex_ref = True
            pbr = mat.get("pbrMetallicRoughness")
            if isinstance(pbr, dict):
                for key in ("baseColorTexture", "metallicRoughnessTexture"):
                    if key in pbr:
                        del pbr[key]
                        removed_any_tex_ref = True

    present_shared_mats.sort()

    # Determine which textures / images / samplers are still referenced by any
    # non-shared material (typically none for landmark GLBs).
    used_tex_indices: set[int] = set()
    for mat in gltf.get("materials", []):
        for ref in _collect_material_tex_refs(mat):
            used_tex_indices.add(int(ref["index"]))

    old_textures = gltf.get("textures", [])
    old_images = gltf.get("images", [])
    old_samplers = gltf.get("samplers", [])

    has_unreferenced_media = (
        len(used_tex_indices) < len(old_textures)
        or (not used_tex_indices and (old_textures or old_images or old_samplers))
    )

    if not removed_any_tex_ref and not has_unreferenced_media:
        return present_shared_mats, False, bytes_before, bytes_before

    # Remap surviving textures, images, and samplers (or drop them completely if unused).
    if not used_tex_indices:
        gltf.pop("textures", None)
        gltf.pop("images", None)
        gltf.pop("samplers", None)
    else:
        tex_remap = {}
        img_remap = {}
        smp_remap = {}
        new_textures = []
        new_images = []
        new_samplers = []
        for old_ti in sorted(used_tex_indices):
            tex = dict(old_textures[old_ti])
            if "source" in tex:
                old_ii = int(tex["source"])
                if old_ii not in img_remap:
                    img_remap[old_ii] = len(new_images)
                    new_images.append(dict(old_images[old_ii]))
                tex["source"] = img_remap[old_ii]
            if "sampler" in tex:
                old_si = int(tex["sampler"])
                if old_si not in smp_remap:
                    smp_remap[old_si] = len(new_samplers)
                    new_samplers.append(dict(old_samplers[old_si]))
                tex["sampler"] = smp_remap[old_si]
            tex_remap[old_ti] = len(new_textures)
            new_textures.append(tex)

        for mat in gltf.get("materials", []):
            for ref in _collect_material_tex_refs(mat):
                ref["index"] = tex_remap[int(ref["index"])]

        gltf["textures"] = new_textures
        if new_images:
            gltf["images"] = new_images
        else:
            gltf.pop("images", None)
        if new_samplers:
            gltf["samplers"] = new_samplers
        else:
            gltf.pop("samplers", None)

    # Collect all still-referenced bufferViews (geometry accessors + any surviving images).
    used_bvs: set[int] = set()
    for acc in gltf.get("accessors", []):
        if "bufferView" in acc:
            used_bvs.add(int(acc["bufferView"]))
        sparse = acc.get("sparse")
        if sparse:
            used_bvs.add(int(sparse["indices"]["bufferView"]))
            used_bvs.add(int(sparse["values"]["bufferView"]))
    for img in gltf.get("images", []):
        if "bufferView" in img:
            used_bvs.add(int(img["bufferView"]))

    old_bvs = gltf.get("bufferViews", [])
    new_bvs = []
    bv_remap: dict[int, int] = {}
    new_bin = bytearray()

    for old_bvi in sorted(used_bvs):
        old_bv = old_bvs[old_bvi]
        if old_bv.get("buffer", 0) != 0:
            raise ValueError(f"{glb_path}: unsupported multi-buffer index {old_bv.get('buffer')}")
        # 4-byte align every bufferView per glTF 2.0 alignment requirements
        pad = (-len(new_bin)) % 4
        if pad:
            new_bin.extend(b"\x00" * pad)

        old_off = old_bv.get("byteOffset", 0)
        blen = old_bv["byteLength"]
        new_bv = dict(old_bv)
        new_bv["byteOffset"] = len(new_bin)
        new_bin.extend(bin_bytes[old_off : old_off + blen])

        bv_remap[old_bvi] = len(new_bvs)
        new_bvs.append(new_bv)

    pad = (-len(new_bin)) % 4
    if pad:
        new_bin.extend(b"\x00" * pad)

    gltf["bufferViews"] = new_bvs
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(new_bin)

    for acc in gltf.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = bv_remap[int(acc["bufferView"])]
        sparse = acc.get("sparse")
        if sparse:
            sparse["indices"]["bufferView"] = bv_remap[int(sparse["indices"]["bufferView"])]
            sparse["values"]["bufferView"] = bv_remap[int(sparse["values"]["bufferView"])]
    for img in gltf.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = bv_remap[int(img["bufferView"])]

    packed = _pack_glb(gltf, bytes(new_bin))
    _validate_glb(packed, orig_sigs)

    tmp_path = glb_path + ".tmp"
    with open(tmp_path, "wb") as fh:
        fh.write(packed)
    os.replace(tmp_path, glb_path)

    return present_shared_mats, True, bytes_before, len(packed)


def _format_subresources(mat_names: list[str]) -> str:
    """Format Godot ConfigFile `_subresources={...}` dictionary cleanly."""
    if not mat_names:
        return "_subresources={}"
    lines = ["_subresources={", '"materials": {']
    for idx, mat_name in enumerate(mat_names):
        comma = "," if idx < len(mat_names) - 1 else ""
        tres_path = f"{SHARED_RES_PREFIX}{mat_name}.tres"
        lines.append(f'"{mat_name}": {{')
        lines.append('"use_external/enabled": true,')
        lines.append(f'"use_external/fallback_path": "{tres_path}",')
        lines.append(f'"use_external/path": "{tres_path}"')
        lines.append(f"}}{comma}")
    lines.append("}")
    lines.append("}")
    return "\n".join(lines)


def _replace_subresources_block(text: str, new_block: str) -> str:
    """Replace single-line or multi-line `_subresources={...}` in a `.glb.import` file."""
    m = re.search(r"(?m)^_subresources=", text)
    if not m:
        sep = "" if text.endswith("\n") else "\n"
        return text + sep + new_block + "\n"

    start = m.start()
    brace_start = text.find("{", m.end())
    if brace_start == -1:
        end_line = text.find("\n", m.end())
        end = len(text) if end_line == -1 else end_line
        return text[:start] + new_block + text[end:]

    depth = 0
    in_str = False
    esc = False
    end = brace_start
    for i in range(brace_start, len(text)):
        ch = text[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
    return text[:start] + new_block + text[end:]


def update_glb_import(glb_path: str, present_shared_mats: list[str]) -> tuple[bool, bool]:
    """Update `<glb_path>.import` to hook up shared `.tres` materials & prevent PNG extraction.

    Returns `(import_exists, modified)`.
    """
    imp_path = glb_path + ".import"
    if not os.path.isfile(imp_path):
        return False, False

    with open(imp_path, "r", encoding="utf-8") as fh:
        orig = fh.read()

    text = orig
    if re.search(r"(?m)^gltf/embedded_image_handling=\d+$", text):
        text = re.sub(
            r"(?m)^gltf/embedded_image_handling=\d+$",
            "gltf/embedded_image_handling=2",
            text,
        )
    else:
        sep = "" if text.endswith("\n") else "\n"
        text = text + sep + "gltf/embedded_image_handling=2\n"

    subres_block = _format_subresources(present_shared_mats)
    text = _replace_subresources_block(text, subres_block)

    if text != orig:
        tmp = imp_path + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        os.replace(tmp, imp_path)
        return True, True
    return True, False


def optimize_shared_png_imports(shared_dir: str) -> tuple[int, int]:
    """Apply `optimize_imports.optimize_import_file` to all `shared/*.png.import` files."""
    if TEXTURES_TOOL_DIR not in sys.path:
        sys.path.insert(0, TEXTURES_TOOL_DIR)
    import optimize_imports

    imp_files = sorted(glob.glob(os.path.join(shared_dir, "*.png.import")))
    changed = 0
    for imp in imp_files:
        if optimize_imports.optimize_import_file(imp):
            changed += 1
    return len(imp_files), changed


def delete_redundant_extracted_pngs(landmarks_dir: str) -> tuple[int, int]:
    """Delete redundant per-GLB `*_lm_*.png` and `*_lm_*.png.import` duplicates."""
    pngs = sorted(glob.glob(os.path.join(landmarks_dir, "*_lm_*.png")))
    imps = sorted(glob.glob(os.path.join(landmarks_dir, "*_lm_*.png.import")))
    for p in pngs:
        os.remove(p)
    for p in imps:
        os.remove(p)
    return len(pngs), len(imps)


def run_godot_import(repo_root: str) -> None:
    """Run `godot --headless --path <repo_root> --import --quit`."""
    env = os.environ.copy()
    local_bin = os.path.expanduser("~/.local/bin")
    env["PATH"] = f"{local_bin}:{env.get('PATH', '')}"
    godot_bin = shutil.which("godot", path=env["PATH"])
    if not godot_bin:
        raise RuntimeError("`godot` executable not found on PATH (checked ~/.local/bin)")
    print(f"dedup_landmark_materials: running `{godot_bin} --headless --path {repo_root} --import --quit` ...")
    res = subprocess.run(
        [godot_bin, "--headless", "--path", repo_root, "--import", "--quit"],
        cwd=repo_root,
        env=env,
        check=False,
    )
    if res.returncode != 0:
        raise RuntimeError(f"Godot --import exited with code {res.returncode}")


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    if "--" in argv:
        cli = argv[argv.index("--") + 1 :]
    elif os.path.basename(argv[0]).lower().startswith("blender"):
        cli = []
    else:
        cli = argv[1:]

    parser = argparse.ArgumentParser(
        description="Deduplicate landmark PBR PNGs into shared BC7 textures & .tres materials."
    )
    parser.add_argument(
        "--landmarks-dir",
        default=os.path.join(REPO_ROOT, "assets", "generated", "landmarks"),
        help="Path to assets/generated/landmarks directory",
    )
    parser.add_argument(
        "--skip-textures",
        action="store_true",
        help="Skip regenerating shared PNGs and .tres files (still strip GLBs & update .import)",
    )
    parser.add_argument(
        "--godot-import",
        action="store_true",
        help="Run the two-pass Godot headless `--import` + BC7 optimization automatically",
    )
    return parser.parse_args(cli)


def main() -> int:
    args = parse_args()
    landmarks_dir = os.path.abspath(args.landmarks_dir)
    shared_dir = os.path.join(landmarks_dir, "shared")

    if not os.path.isdir(landmarks_dir):
        print(f"ERROR: landmarks directory does not exist: {landmarks_dir}", file=sys.stderr)
        return 1

    # 1 & 2. Export 30 shared 512x512 PBR PNGs + 11 shared StandardMaterial3D .tres files
    if not args.skip_textures:
        total_pngs, written_pngs = export_shared_textures(shared_dir)
        total_tres, written_tres = export_shared_materials(shared_dir)
        print(
            f"dedup_landmark_materials: shared textures={total_pngs} ({written_pngs} updated), "
            f"shared .tres={total_tres} ({written_tres} updated) in {shared_dir}"
        )

    # 3. Strip duplicate embedded images from every *.glb in landmarks_dir
    glbs = sorted(glob.glob(os.path.join(landmarks_dir, "*.glb")))
    glb_mats: dict[str, list[str]] = {}
    total_before = 0
    total_after = 0
    stripped_count = 0
    for glb_path in glbs:
        mats, modified, b_before, b_after = strip_glb_embedded_images(glb_path)
        glb_mats[glb_path] = mats
        total_before += b_before
        total_after += b_after
        if modified:
            stripped_count += 1
        print(
            f"  {os.path.basename(glb_path):36s} {b_before / 1024:7.1f} KB -> {b_after / 1024:7.1f} KB"
            f"  ({'stripped' if modified else 'already clean'}, {len(mats)} shared mats)"
        )

    print(
        f"dedup_landmark_materials: processed {len(glbs)} GLBs ({stripped_count} stripped), "
        f"GLB total {total_before / (1024 * 1024):.2f} MB -> {total_after / (1024 * 1024):.2f} MB"
    )

    # 4. Update existing *.glb.import files & delete redundant *_lm_*.png{,.import}
    imp_updated = 0
    imp_missing = 0
    for glb_path, mats in glb_mats.items():
        exists, changed = update_glb_import(glb_path, mats)
        if not exists:
            imp_missing += 1
        elif changed:
            imp_updated += 1

    del_pngs, del_imps = delete_redundant_extracted_pngs(landmarks_dir)
    opt_scanned, opt_changed = optimize_shared_png_imports(shared_dir)
    print(
        f"dedup_landmark_materials: .glb.import updated={imp_updated} (missing={imp_missing}), "
        f"shared .png.import BC7-optimized={opt_changed}/{opt_scanned}, "
        f"deleted duplicates={del_pngs} PNGs + {del_imps} .png.import"
    )

    # Optional two-pass Godot headless import so newly added GLBs & shared PNGs get
    # `.import` files, BC7 compression, external material bindings, and clean re-import.
    if args.godot_import:
        run_godot_import(REPO_ROOT)
        opt_scanned, opt_changed = optimize_shared_png_imports(shared_dir)
        imp_updated2 = 0
        for glb_path, mats in glb_mats.items():
            exists, changed = update_glb_import(glb_path, mats)
            if not exists:
                raise RuntimeError(f"Godot --import did not create {glb_path}.import")
            if changed:
                imp_updated2 += 1
        del_pngs2, del_imps2 = delete_redundant_extracted_pngs(landmarks_dir)
        print(
            f"dedup_landmark_materials: post-pass1 BC7-optimized={opt_changed}/{opt_scanned}, "
            f".glb.import updated={imp_updated2}, stray duplicates deleted={del_pngs2} PNGs + {del_imps2} .import"
        )
        run_godot_import(REPO_ROOT)
        del_pngs3, del_imps3 = delete_redundant_extracted_pngs(landmarks_dir)
        if del_pngs3 or del_imps3:
            raise RuntimeError(
                f"Unexpected extracted PNG duplicates reappeared after Godot import: {del_pngs3} PNGs"
            )
        print("dedup_landmark_materials: two-pass Godot import & BC7 deduplication complete!")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
