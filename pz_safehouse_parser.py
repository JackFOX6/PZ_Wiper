#!/usr/bin/env python3
import sys
import struct
import re
import json
import os

def parse_safehouses(file_path):
    if not os.path.exists(file_path):
        return []

    try:
        with open(file_path, "rb") as f:
            data = f.read()
    except Exception as e:
        return []

    # Buscamos patron: 00 00 XX XX 00 00 YY YY 00 00 00 WW 00 00 00 HH (W y H menores a 255)
    # En bytes: \x00\x00(..)\x00\x00(..)\x00\x00\x00(.)\x00\x00\x00(.)
    pattern = re.compile(b'\x00\x00(..)\x00\x00(..)\x00\x00\x00(.)\x00\x00\x00(.)', re.DOTALL)
    
    safehouses = []
    seen = set()

    for match in pattern.finditer(data):
        xb = match.group(1)
        yb = match.group(2)
        wb = match.group(3)
        hb = match.group(4)
        
        try:
            x = struct.unpack(">H", xb)[0]
            y = struct.unpack(">H", yb)[0]
            w = struct.unpack(">B", wb)[0]
            h = struct.unpack(">B", hb)[0]
        except:
            continue
            
        # Filtros de sanidad: En Zomboid los coords de jugador activos suelen ser mayores a 1000
        # W y H de un safehouse normal son > 0
        if x < 1000 or y < 1000 or w == 0 or h == 0:
            continue
            
        # Leer el string owner que viene justo despues de los 16 bytes. 
        # Formato del string: [2 bytes Length Int16 BigEndian] [String]
        end_idx = match.end()
        if end_idx + 2 <= len(data):
            try:
                slen = struct.unpack(">H", data[end_idx:end_idx+2])[0]
                if 0 < slen < 50:
                    owner_bytes = data[end_idx+2:end_idx+2+slen]
                    # Solo decodificamos si no hay caracteres raros o binarios en el nombre
                    owner = owner_bytes.decode("utf-8")
                    if not owner.isprintable():
                        continue
                        
                    # Prevenir duplicados en caso de encontrar el mismo patron accidentalmente
                    sig = f"{x},{y},{w},{h}"
                    if sig not in seen:
                        seen.add(sig)
                        safehouses.append({
                            "owner": owner,
                            "x": x,
                            "y": y,
                            "w": w,
                            "h": h
                        })
            except:
                pass
                
    return safehouses

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"safehouses": []}))
        sys.exit(1)
        
    map_meta_path = sys.argv[1]
    results = parse_safehouses(map_meta_path)
    
    print(json.dumps({"safehouses": results}))
