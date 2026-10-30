import sys
import struct

if len(sys.argv) < 3:
    print("Uso: bin2hex.py <input.bin> <output.hex> [words_count]")
    sys.exit(1)

bin_file = sys.argv[1]
hex_file = sys.argv[2]
words_count = int(sys.argv[3]) if len(sys.argv) > 3 else 4096

with open(bin_file, "rb") as fin:
    data = fin.read()

mem = [0] * words_count
for i in range(0, len(data), 4):
    chunk = data[i:i+4]
    if len(chunk) == 4 and (i // 4) < words_count:
        mem[i // 4] = struct.unpack("<I", chunk)[0]

with open(hex_file, "w") as fout:
    for val in mem:
        fout.write(f"{val:08x}\n")

print(f">>> {hex_file} gerado com sucesso ({len(data)} bytes, {words_count} palavras).")
