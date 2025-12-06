"""
Heuristic decoder for Balatro/Steamodded save files (.jkr).

Tries multiple LZ4 variants (frame, block with/without size headers) and
falls back to zlib. Can emit raw bytes, JSON, or a Lua-ish table dump,
and prints a quick summary (method, size, hash) for easy comparisons.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

try:
    import lz4.block
    import lz4.frame
except ImportError:
    print("Missing dependency: install with `pip install lz4`")
    sys.exit(1)

import zlib


def try_decode(data: bytes):
    attempts = []

    # 1) LZ4 frame
    attempts.append(("lz4.frame", lambda d: lz4.frame.decompress(d)))

    # 2) LZ4 block, no header
    attempts.append(("lz4.block (no header)", lambda d: lz4.block.decompress(d)))

    # 3) LZ4 block with a 4-byte little-endian size header (Love2D style)
    def lz4_with_size_le(d: bytes):
        if len(d) < 4:
            raise ValueError("too short for size header")
        size = struct.unpack("<I", d[:4])[0]
        return lz4.block.decompress(d[4:], uncompressed_size=size)

    attempts.append(("lz4.block (LE size header)", lz4_with_size_le))

    # 4) LZ4 block with a 4-byte big-endian size header
    def lz4_with_size_be(d: bytes):
        if len(d) < 4:
            raise ValueError("too short for size header")
        size = struct.unpack(">I", d[:4])[0]
        return lz4.block.decompress(d[4:], uncompressed_size=size)

    attempts.append(("lz4.block (BE size header)", lz4_with_size_be))

    # 5) zlib (standard)
    attempts.append(("zlib", lambda d: zlib.decompress(d)))
    # 6) zlib raw deflate (wbits=-15)
    attempts.append(("zlib raw", lambda d: zlib.decompress(d, wbits=-15)))

    # 7) LZ4 block with brute-forced size guesses (common when size is unknown)
    def lz4_bruteforce(d: bytes):
        # Try a range of plausible sizes up to 64 MB
        guesses = list(range(256 * 1024, 8 * 1024 * 1024 + 1, 256 * 1024))
        guesses += list(range(9 * 1024 * 1024, 32 * 1024 * 1024 + 1, 1024 * 1024))
        guesses += [48 * 1024 * 1024, 64 * 1024 * 1024]
        for sz in guesses:
            try:
                out = lz4.block.decompress(d, uncompressed_size=sz)
                return out
            except Exception:
                continue
        raise ValueError("bruteforce size guesses failed")

    attempts.append(("lz4.block (bruteforce size)", lz4_bruteforce))

    last_err = None
    for name, fn in attempts:
        try:
            out = fn(data)
            return name, out
        except Exception as e:
            last_err = f"{name}: {e}"
    raise RuntimeError(f"Failed to decode with known methods. Last error: {last_err}")


def summarize(raw: bytes, method: str):
    sha = hashlib.sha256(raw).hexdigest()
    return f"Decoded with {method}, {len(raw)} bytes, sha256={sha}"


def decode_file(input_path: Path, args):
    if not input_path.exists():
        raise FileNotFoundError(f"Missing {input_path}")

    data = input_path.read_bytes()
    method, raw = try_decode(data)
    summary = summarize(raw, method)

    text = None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        pass

    if text:
        if args.print:
            print(text[: args.print])

        # Try JSON
        try:
            obj = json.loads(text)
            if args.json_out:
                Path(args.json_out).write_text(json.dumps(obj, indent=2))
            elif args.print_json:
                print(json.dumps(obj, indent=2)[: args.print_json])
            return summary
        except Exception:
            pass

        # If it looks like a Lua table dump (starts with return {)
        if text.lstrip().startswith("return {"):
            lua_out = Path(args.lua_out) if args.lua_out else Path("save.lua.txt")
            lua_out.write_text(text)
            return summary + f"\nWrote Lua-like table to {lua_out}"

    # Fallback: raw bytes dump
    raw_out = Path(args.raw_out) if args.raw_out else Path("save.decompressed.bin")
    raw_out.write_bytes(raw)
    return summary + f"\nCould not JSON-decode. Wrote decompressed bytes to {raw_out}"


def build_parser():
    p = argparse.ArgumentParser(description="Decode Balatro/LZ4/zlib .jkr saves")
    p.add_argument("input", nargs="?", default="save.jkr", help="Input .jkr file (default: save.jkr)")
    p.add_argument("--raw-out", help="Where to write raw decompressed bytes (default: save.decompressed.bin)")
    p.add_argument("--lua-out", help="Where to write Lua-like table output (default: save.lua.txt)")
    p.add_argument("--json-out", help="Where to write JSON if parsing succeeds")
    p.add_argument("--print", type=int, metavar="N", help="Print first N characters of decoded text")
    p.add_argument("--print-json", type=int, metavar="N", help="Print first N characters of decoded JSON (if parsed)")
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()

    try:
        summary = decode_file(Path(args.input), args)
    except Exception as e:
        print(f"Decode failed: {e}")
        sys.exit(1)

    print(summary)


if __name__ == "__main__":
    main()
