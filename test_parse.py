#!/usr/bin/env python3
"""
test_parse.py — Test runner para validar la suite de Python y parsers de PZ_Wiper (B42 Stable)
"""

import os
import sys
import tempfile
import struct
import json

# Importar parser local
from pz_safehouse_parser import parse_safehouses

def create_synthetic_map_meta() -> str:
    """Crea un map_meta.bin sintético para validar el parser de safehouses."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".bin")

    # Estructura: 00 00 XX XX 00 00 YY YY 00 00 00 WW 00 00 00 HH + Int16Len + String
    x, y, w, h = 10230, 14520, 15, 20
    owner = "j4ck_tester"
    owner_bytes = owner.encode("utf-8")

    header = struct.pack(">HHBB", x, y, w, h)
    # Recrear patrón: 00 00 XX XX 00 00 YY YY 00 00 00 WW 00 00 00 HH
    pattern_bytes = (
        b'\x00\x00' + struct.pack(">H", x) +
        b'\x00\x00' + struct.pack(">H", y) +
        b'\x00\x00\x00' + struct.pack(">B", w) +
        b'\x00\x00\x00' + struct.pack(">B", h) +
        struct.pack(">H", len(owner_bytes)) + owner_bytes
    )

    tmp.write(b"HEADER_DUMMY_DATA_12345" + pattern_bytes + b"FOOTER_DATA")
    tmp.close()
    return tmp.name

def run_tests():
    print("==================================================")
    print(" Running PZ_Wiper B42 Stable Python Test Suite")
    print("==================================================")

    # Test 1: Parser de Safehouses sintético
    syn_file = create_synthetic_map_meta()
    try:
        results = parse_safehouses(syn_file)
        assert len(results) > 0, "No se detectaron safehouses en el archivo sintético"
        sh = results[0]
        assert sh["x"] == 10230, f"X esperado 10230, obtenido {sh['x']}"
        assert sh["y"] == 14520, f"Y esperado 14520, obtenido {sh['y']}"
        assert sh["w"] == 15, f"W esperado 15, obtenido {sh['w']}"
        assert sh["h"] == 20, f"H esperado 20, obtenido {sh['h']}"
        assert sh["owner"] == "j4ck_tester", f"Owner esperado 'j4ck_tester', obtenido {sh['owner']}"
        print(" [OK] Test 1: Parser binario de Safehouses funcional.")
    finally:
        if os.path.exists(syn_file):
            os.remove(syn_file)

    # Test 2: Archivo no existente
    res_empty = parse_safehouses("/tmp/non_existent_map_meta_12345.bin")
    assert res_empty == [], "Un archivo inexistente debe retornar lista vacía"
    print(" [OK] Test 2: Manejo defensivo de archivos inexistentes.")

    print("\n✓ ¡Todos los tests pasaron exitosamente!")

if __name__ == "__main__":
    run_tests()
