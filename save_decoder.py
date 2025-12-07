"""
Heuristic decoder for Balatro/Steamodded save files (.jkr).

Uses zlib raw (deflate, wbits=-15) to decompress. Can emit a Lua-ish table
dump by default, or raw bytes as a fallback,
"""
import argparse
import hashlib
import struct
import sys
from pathlib import Path
import re

import zlib


def try_decode(data: bytes):
    try:
        out = zlib.decompress(data, wbits=-15)
        return "zlib raw", out
    except Exception as e:
        raise RuntimeError(f"Failed to decode with zlib raw: {e}")


def summarize(raw: bytes, method: str):
    sha = hashlib.sha256(raw).hexdigest()
    return f"Decoded with {method}, {len(raw)} bytes, sha256={sha}"


# Heuristic pretty-printer for a Lua-style table dump
def format_lua_table(text: str) -> str:
    """
    Heuristic pretty-printer for a Lua-style table dump.

    It assumes the text is valid Lua and mainly reflows braces and commas
    into a more readable, indented layout. It is intentionally simple and
    is not a full Lua parser.
    """
    out_chars = []
    indent = 0
    in_string = False
    string_quote = ""
    escape = False

    def indent_str(level: int) -> str:
        return "  " * max(level, 0)

    i = 0
    while i < len(text):
        ch = text[i]

        if in_string:
            out_chars.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == string_quote:
                in_string = False
        else:
            if ch in ("\"", "'"):
                in_string = True
                string_quote = ch
                out_chars.append(ch)
            elif ch == "{":
                # Look ahead to see if this is an empty table: {} (possibly with whitespace)
                j = i + 1
                while j < len(text) and text[j] in " \t\r\n":
                    j += 1
                if j < len(text) and text[j] == "}":
                    # Emit {} directly, no extra indentation/newlines
                    out_chars.append("{}")
                    # Skip over the closing brace in the main loop
                    i = j
                else:
                    out_chars.append("{")
                    indent += 1
                    out_chars.append("\n" + indent_str(indent))
            elif ch == "}":
                indent -= 1
                # If the last piece is just a newline + indent (from a trailing comma),
                # reuse it instead of adding another newline to avoid blank lines.
                if out_chars and out_chars[-1].startswith("\n"):
                    out_chars[-1] = "\n" + indent_str(indent) + ch
                else:
                    out_chars.append("\n" + indent_str(indent) + ch)
            elif ch == ",":
                out_chars.append(ch)
                out_chars.append("\n" + indent_str(indent))
            elif ch in " \t\r\n":
                # Drop original whitespace outside of strings; formatting controls layout
                pass
            else:
                out_chars.append(ch)
        i += 1

    return "".join(out_chars)


# Regex and helper for sorting Lua table keys per indent block
key_pattern = re.compile(r'^(\s*)(\[\s*"(.*?)"\s*\]|[A-Za-z_][A-Za-z0-9_]*)\s*=')


def sort_lua_keys(text: str) -> str:
    """Sort Lua table key/value lines alphabetically by key within each indent block.

    Assumes the text has already been pretty-printed so that each key/value
    pair appears on a single line at its indentation level, like:

        ["foo"]=1,
        ["bar"]=2,

    It does not fully parse Lua; it just groups consecutive lines that look
    like key/value pairs with the same leading whitespace and sorts
    those lines by their key name.
    """
    lines = text.splitlines()
    out_lines = []
    i = 0
    n = len(lines)

    while i < n:
        m = key_pattern.match(lines[i])
        if not m:
            out_lines.append(lines[i])
            i += 1
            continue

        indent = m.group(1)
        indent_level = len(indent) // 2
        block = []

        # Collect a block of consecutive key/value lines with the same indent level
        while i < n:
            m2 = key_pattern.match(lines[i])
            if not m2:
                break
            level2 = len(m2.group(1)) // 2
            if level2 != indent_level:
                break
            block.append(lines[i])
            i += 1

        def key_of(line: str) -> str:
            m3 = key_pattern.match(line)
            if not m3:
                return line
            # Group 3 is the inner name for ["name"] style keys
            key = m3.group(3)
            if key is None:
                # Fallback: the whole key token (identifier-style key)
                key = m3.group(2)
            return str(key)

        block.sort(key=key_of)
        out_lines.extend(block)

    return "\n".join(out_lines)


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

        formatted = format_lua_table(text)
        formatted = sort_lua_keys(formatted)
        if args.lua_out:
            lua_out = Path(args.lua_out)
        else:
            # default: jkrs/decode/<input_stem>.lua
            out_dir = Path("jkrs") / "decode"
            out_dir.mkdir(parents=True, exist_ok=True)
            lua_out = out_dir / f"{input_path.stem}.lua"
        lua_out.write_text(formatted)
        return summary + f"\nWrote formatted Lua-like text to {lua_out}"

    # Fallback: raw bytes dump
    if args.raw_out:
        raw_out = Path(args.raw_out)
    else:
        out_dir = Path("jkrs") / "decode"
        out_dir.mkdir(parents=True, exist_ok=True)
        raw_out = out_dir / f"{input_path.stem}.decompressed.bin"
    raw_out.write_bytes(raw)
    return summary + f"\nCould not UTF-8 decode. Wrote decompressed bytes to {raw_out}"


def build_parser():
    p = argparse.ArgumentParser(description="Decode Balatro .jkr save files")
    p.add_argument(
        "input",
        nargs="?",
        help="Input .jkr file; if omitted, decode all .jkr files in the ./jkrs directory",
    )
    p.add_argument("--raw-out", help="Where to write raw decompressed bytes (default: save.decompressed.bin)")
    p.add_argument(
        "--lua-out",
        help="Where to write Lua-like table output (default: jkrs/decode/<input_stem>.lua)",
    )
    p.add_argument("--print", type=int, metavar="N", help="Print first N characters of decoded text")
    return p


def main():
    parser = build_parser()
    args = parser.parse_args()

    # Determine which inputs to process
    inputs = []
    if args.input:
        inputs = [Path(args.input)]
    else:
        jkrs_dir = Path("jkrs")
        if not jkrs_dir.exists():
            print("No input file given and ./jkrs directory does not exist.")
            sys.exit(1)
        inputs = sorted(p for p in jkrs_dir.glob("*.jkr") if p.is_file())
        if not inputs:
            print("No .jkr files found in ./jkrs")
            sys.exit(1)

    any_failed = False
    for path in inputs:
        try:
            summary = decode_file(path, args)
            print(f"{path}: {summary}")
        except Exception as e:
            any_failed = True
            print(f"{path}: Decode failed: {e}")

    if any_failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
