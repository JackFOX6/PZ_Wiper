#!/usr/bin/env python3
"""
pz_safehouse_parser.py — Project Zomboid Build 42 Stable Safehouse Binary Parser

Escanea archivos map_meta.bin para extraer refugios (safehouses) registrados
por los jugadores, decodificando coordenadas y nombres de dueños de forma segura.
"""

import sys
import struct
import re
import json
import os
import argparse

def parse_safehouses(file_path: str) -> list[dict]:
    """
    Parses safehouses from map_meta.bin.
    Returns a list of dicts containing owner, x, y, w, h.
    """
    if not os.path.exists(file_path):
        return []

    try:
        with open(file_path, "rb") as f:
            data = f.read()
    except Exception as e:
        sys.stderr.write(f"[WARN] Error al leer {file_path}: {e}\n")
        return []

    # Patron binario: 00 00 XX XX 00 00 YY YY 00 00 00 WW 00 00 00 HH (W y H < 255)
    pattern = re.compile(b'\x00\x00(..)\x00\x00(..)\x00\x00\x00(.)\x00\x00\x00(.)', re.DOTALL)
    
    safehouses = []
    seen = set()

    for match in pattern.finditer(data):
        xb, yb, wb, hb = match.group(1), match.group(2), match.group(3), match.group(4)
        
        try:
            x = struct.unpack(">H", xb)[0]
            y = struct.unpack(">H", yb)[0]
            w = struct.unpack(">B", wb)[0]
            h = struct.unpack(">B", hb)[0]
        except Exception:
            continue
            
        # Filtros de cordura para Zomboid Build 42:
        # Coordenadas activas > 100 y dimensiones mayores a 0
        if x < 100 or y < 100 or w == 0 or h == 0 or w > 500 or h > 500:
            continue
            
        # Leer el string de propietario que sigue inmediatamente a la estructura de coords
        end_idx = match.end()
        if end_idx + 2 <= len(data):
            try:
                slen = struct.unpack(">H", data[end_idx:end_idx+2])[0]
                if 0 < slen < 64:
                    owner_bytes = data[end_idx+2:end_idx+2+slen]
                    # Intentar decodificación UTF-8 con fallback a latin-1
                    try:
                        owner = owner_bytes.decode("utf-8")
                    except UnicodeDecodeError:
                        owner = owner_bytes.decode("latin-1", errors="ignore")
                        
                    if not owner.isprintable() or not owner.strip():
                        continue
                        
                    sig = f"{x},{y},{w},{h}"
                    if sig not in seen:
                        seen.add(sig)
                        safehouses.append({
                            "owner": owner.strip(),
                            "x": x,
                            "y": y,
                            "w": w,
                            "h": h
                        })
            except Exception:
                pass
                
    return safehouses

def main():
    parser = argparse.ArgumentParser(description="PZ B42 Safehouse Binary Parser")
    parser.add_argument("map_meta", nargs="?", default="", help="Ruta al archivo map_meta.bin")
    parser.add_argument("--format", choices=["json", "summary"], default="json", help="Formato de salida")
    args = parser.parse_args()

    if not args.map_meta:
        print(json.dumps({"safehouses": []}))
        sys.exit(0)

    safehouses = parse_safehouses(args.map_meta)

    if args.format == "json":
        print(json.dumps({"safehouses": safehouses}, indent=2 if sys.stdout.isatty() else None))
    else:
        print(f"Total safehouses detectados: {len(safehouses)}")
        for sh in safehouses:
            print(f"  Owner: {sh['owner']:<20} | Coords: ({sh['x']},{sh['y']}) {sh['w']}x{sh['h']}")

if __name__ == "__main__":
    main()
