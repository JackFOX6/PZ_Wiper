#!/usr/bin/env python3
"""
sync_workshop.py
----------------
Lee Mods= desde servertest.ini y construye WorkshopItems= escaneando
los mod.info descargados en el directorio de Steam Workshop.

Uso:
    python3 sync_workshop.py [--ini PATH] [--workshop PATH] [--dry-run]
"""

import argparse
import os
import re
import sys
from pathlib import Path

# ── Rutas por defecto ──────────────────────────────────────────────────────────
DEFAULT_INI = Path(__file__).parent.parent / "Server" / "servertest.ini"
DEFAULT_WORKSHOP = Path.home() / ".local/share/Steam/steamapps/workshop/content/108600"


def build_mod_map(workshop_dir: Path) -> dict[str, str]:
    """
    Escanea todos los mod.info dentro del directorio de Workshop y devuelve
    un dict { mod_id_lower: workshop_id } para lookup case-insensitive.
    Un mismo workshopID puede tener múltiples mods (ej. WorldDecay + WorldDecay_Maniks...).
    """
    mod_map: dict[str, str] = {}     # mod_id (lower) → workshop_id (str)
    mod_map_raw: dict[str, str] = {} # mod_id (original case) → workshop_id

    if not workshop_dir.exists():
        print(f"[ERROR] Directorio de Workshop no encontrado: {workshop_dir}", file=sys.stderr)
        sys.exit(1)

    for workshop_id_dir in workshop_dir.iterdir():
        if not workshop_id_dir.is_dir():
            continue
        workshop_id = workshop_id_dir.name

        # Busca todos los mod.info en cualquier subcarpeta de este item
        for mod_info_path in workshop_id_dir.rglob("mod.info"):
            with open(mod_info_path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if line.lower().startswith("id="):
                        mod_id = line.split("=", 1)[1].strip()
                        mod_map[mod_id.lower()] = workshop_id
                        mod_map_raw[mod_id] = workshop_id
                        break  # solo necesitamos el id= de este mod.info

    return mod_map, mod_map_raw


def read_ini_field(ini_path: Path, field: str) -> str | None:
    """Devuelve el valor de un campo clave=valor en el .ini (primera ocurrencia)."""
    pattern = re.compile(rf"^\s*{re.escape(field)}\s*=\s*(.*)", re.IGNORECASE)
    with open(ini_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = pattern.match(line)
            if m:
                return m.group(1).strip()
    return None


def write_ini_field(ini_path: Path, field: str, new_value: str) -> bool:
    """Reemplaza el valor de un campo en el .ini. Devuelve True si lo encontró."""
    pattern = re.compile(rf"^(\s*{re.escape(field)}\s*=\s*).*", re.IGNORECASE)
    lines = ini_path.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    found = False
    for i, line in enumerate(lines):
        if pattern.match(line):
            ending = "\r\n" if line.endswith("\r\n") else "\n"
            lines[i] = f"{field}={new_value}{ending}"
            found = True
            break
    if found:
        ini_path.write_text("".join(lines), encoding="utf-8")
    return found


def main():
    parser = argparse.ArgumentParser(description="Sincroniza WorkshopItems= desde Mods= en servertest.ini")
    parser.add_argument("--ini",      type=Path, default=DEFAULT_INI,      help="Ruta al servertest.ini")
    parser.add_argument("--workshop", type=Path, default=DEFAULT_WORKSHOP,  help="Ruta a la carpeta 108600 de Workshop")
    parser.add_argument("--dry-run",  action="store_true",                  help="Muestra el resultado sin modificar el archivo")
    args = parser.parse_args()

    # 1. Verificar que el ini existe
    if not args.ini.exists():
        print(f"[ERROR] No se encontró el archivo: {args.ini}", file=sys.stderr)
        sys.exit(1)

    # 2. Leer Mods= del ini
    mods_raw = read_ini_field(args.ini, "Mods")
    if not mods_raw:
        print("[ERROR] No se encontró la línea Mods= en el .ini", file=sys.stderr)
        sys.exit(1)

    mod_ids = [m.strip() for m in mods_raw.split(";") if m.strip()]
    print(f"[INFO] {len(mod_ids)} mods encontrados en Mods=")

    # 3. Construir mapa mod_id → workshop_id desde el disco
    print(f"[INFO] Escaneando Workshop en: {args.workshop}")
    mod_map_lower, mod_map_raw = build_mod_map(args.workshop)
    print(f"[INFO] {len(mod_map_lower)} mod IDs indexados desde el disco")

    # 4. Resolver cada mod a su Workshop ID
    workshop_ids: list[str] = []
    seen_workshop: set[str] = set()  # evitar duplicados si un pack tiene varios mods
    not_found: list[str] = []

    for mod_id in mod_ids:
        wid = mod_map_lower.get(mod_id.lower())
        if wid:
            if wid not in seen_workshop:
                workshop_ids.append(wid)
                seen_workshop.add(wid)
        else:
            not_found.append(mod_id)

    # 5. Reporte
    print()
    print("─" * 60)
    print(f"  Mods resueltos : {len(workshop_ids)}")
    print(f"  No encontrados : {len(not_found)}")
    print("─" * 60)

    if not_found:
        print("\n[ADVERTENCIA] Los siguientes mods NO se encontraron en el Workshop local:")
        for m in not_found:
            print(f"    ✗  {m}")
        print("   → Puede que no estén descargados, o que el nombre en Mods= no coincida")
        print("     exactamente con el campo id= en su mod.info\n")

    new_workshop_value = ";".join(workshop_ids)
    print(f"\n[RESULTADO] WorkshopItems={new_workshop_value}\n")

    # 6. Escribir o mostrar
    if args.dry_run:
        print("[DRY-RUN] No se modificó el archivo. Pasa sin --dry-run para aplicar.")
    else:
        ok = write_ini_field(args.ini, "WorkshopItems", new_workshop_value)
        if ok:
            print(f"[OK] {args.ini} actualizado correctamente.")
        else:
            print(f"[ERROR] No se encontró WorkshopItems= en {args.ini}. Agrégalo manualmente.", file=sys.stderr)


if __name__ == "__main__":
    main()
