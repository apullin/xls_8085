#!/usr/bin/env python3
"""Convert a flat binary to Verilog $readmemh format.

Usage: python3 bin2hex.py input.bin > output.hex

Output format: one hex byte per line, with @ADDR annotations.
Suitable for: $readmemh("output.hex", mem) where mem is byte-addressed.
"""
import sys

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} input.bin > output.hex", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    print(f"@0000")
    for i, b in enumerate(data):
        print(f"{b:02X}")

if __name__ == "__main__":
    main()
