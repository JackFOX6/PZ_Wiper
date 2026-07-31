#!/usr/bin/env bash
# =============================================================================
#  pz_coords.sh — Herramienta de conversión de coordenadas PZ Build 42
#
#  PROPOSITO:
#    Convierte coordenadas del juego (tiles/world squares) a archivos de chunk
#    y viceversa. Usalo ANTES de hacer un wipe selectivo con pz_wipe.sh para
#    identificar exactamente que chunks contienen tu base.
#
#  DESDE DONDE EJECUTAR:
#    Puedes ejecutarlo desde CUALQUIER directorio. Usa rutas absolutas internas.
#
#      ~/Zomboid/pz_coords.sh tile 10230 14520
#      /home/j4ck/Zomboid/pz_coords.sh tile 10230 14520
#
#    NO necesitas estar dentro de ~/Zomboid/ para ejecutarlo.
#
#  ADAPTAR PARA EL VPS:
#    Solo edita PZ_BASE_DIR y SERVER_NAME abajo, igual que en pz_wipe.sh.
#
#  COMANDOS:
#    tile  X Y             -> que chunk corresponde a ese tile del juego
#    chunk CX CY           -> que tiles cubre ese archivo de chunk
#    recent [minutos]      -> chunks modificados en los ultimos N minutos
#    scan "X1,Y1,X2,Y2"   -> listar todos los chunks en una zona de tiles
#
#  COMO VER TUS COORDENADAS EN PZ B42:
#    En el juego, presiona F11 para abrir el menu de debug.
#    Las coordenadas que aparecen son "world squares" (tiles).
#    Ejemplo: estas parado en X=10234, Y=14523 en el juego.
#    -> tu chunk es map/1023/1452.bin
#    -> para ver eso: pz_coords.sh tile 10234 14523
#
# =============================================================================

set -euo pipefail

# ============================================================
#  CONFIGURACION — Edita igual que en pz_wipe.sh
# ============================================================
PZ_BASE_DIR="/home/j4ck/Zomboid"
SERVER_NAME="servertest"

# Auto-detección inteligente del save si SERVER_NAME por defecto no existe en disco
if [[ ! -d "${PZ_BASE_DIR}/Saves/Multiplayer/${SERVER_NAME}" && -d "${PZ_BASE_DIR}/Saves/Multiplayer" ]]; then
    map_saves=()
    mapfile -t map_saves < <(ls -1 "${PZ_BASE_DIR}/Saves/Multiplayer" 2>/dev/null || true)
    if [[ ${#map_saves[@]} -eq 1 && -n "${map_saves[0]:-}" ]]; then
        SERVER_NAME="${map_saves[0]}"
    fi
fi

# Rutas derivadas (no editar)
SAVE_DIR="${PZ_BASE_DIR}/Saves/Multiplayer/${SERVER_NAME}"

# Colores
CYN='\033[0;36m'; GRN='\033[0;32m'; YEL='\033[1;33m'; MAG='\033[0;35m'
BLD='\033[1m'; RST='\033[0m'; DIM='\033[2m'

print_header() {
    echo -e "${BLD}============================================${RST}"
    echo -e "${BLD}  PZ B42 -- Conversor de Coordenadas${RST}"
    echo -e "${BLD}============================================${RST}"
    echo -e "  ${DIM}Save: ${SAVE_DIR}${RST}"
    echo ""
}

cmd="${1:-help}"
shift || true

case "$cmd" in

    tile)
        TILE_X="${1:-}"
        TILE_Y="${2:-}"
        if [[ -z "$TILE_X" || -z "$TILE_Y" ]]; then
            echo "Uso: $0 tile <X> <Y>"
            echo "Ejemplo: $0 tile 10230 14520"
            exit 1
        fi
        print_header
        CHUNK_X=$((TILE_X / 10))
        CHUNK_Y=$((TILE_Y / 10))
        TILE_X_MIN=$((CHUNK_X * 10))
        TILE_Y_MIN=$((CHUNK_Y * 10))
        CELL_X=$((CHUNK_X / 30))
        CELL_Y=$((CHUNK_Y / 30))
        echo -e "  ${CYN}Tile ingresado:${RST}    X=${TILE_X}, Y=${TILE_Y}"
        echo ""
        echo -e "  ${GRN}Archivo de chunk:${RST}  ${SAVE_DIR}/map/${CHUNK_X}/${CHUNK_Y}.bin"
        echo -e "  ${GRN}Rango del chunk:${RST}   tiles ${TILE_X_MIN}-$((TILE_X_MIN+9)), ${TILE_Y_MIN}-$((TILE_Y_MIN+9))"
        echo -e "  ${GRN}Celda del mapa:${RST}    Cell(${CELL_X}, ${CELL_Y})"
        echo ""
        FILE="${SAVE_DIR}/map/${CHUNK_X}/${CHUNK_Y}.bin"
        if [[ -f "$FILE" ]]; then
            SIZE=$(du -sh "$FILE" | cut -f1)
            MOD=$(date -r "$FILE" "+%Y-%m-%d %H:%M:%S")
            echo -e "  ${GRN}OK El chunk EXISTE${RST} en el save (${SIZE}, modificado: ${MOD})"
        else
            echo -e "  ${YEL}AVISO: El chunk NO existe aun${RST} (tile no explorado)"
        fi
        echo ""
        echo -e "  ${DIM}Para preservar esta zona en pz_wipe.sh -> Modo 3 -> Opcion A:${RST}"
        echo -e "  ${CYN}Zona: ${TILE_X_MIN},${TILE_Y_MIN},$((TILE_X_MIN+9)),$((TILE_Y_MIN+9))${RST}"
        ;;

    chunk)
        CX="${1:-}"
        CY="${2:-}"
        if [[ -z "$CX" || -z "$CY" ]]; then
            echo "Uso: $0 chunk <chunk_X> <chunk_Y>"
            echo "Ejemplo: $0 chunk 1023 1452"
            exit 1
        fi
        print_header
        TILE_X_MIN=$((CX * 10))
        TILE_Y_MIN=$((CY * 10))
        CELL_X=$((CX / 30))
        CELL_Y=$((CY / 30))
        echo -e "  ${CYN}Archivo:${RST}  ${SAVE_DIR}/map/${CX}/${CY}.bin"
        echo ""
        echo -e "  ${GRN}Cubre tiles X:${RST}  ${TILE_X_MIN} - $((TILE_X_MIN+9))"
        echo -e "  ${GRN}Cubre tiles Y:${RST}  ${TILE_Y_MIN} - $((TILE_Y_MIN+9))"
        echo -e "  ${GRN}Celda:${RST}          Cell(${CELL_X}, ${CELL_Y})"
        echo ""
        FILE="${SAVE_DIR}/map/${CX}/${CY}.bin"
        if [[ -f "$FILE" ]]; then
            SIZE=$(du -sh "$FILE" | cut -f1)
            MOD=$(date -r "$FILE" "+%Y-%m-%d %H:%M:%S")
            echo -e "  ${GRN}OK Existe:${RST} ${SIZE}, modificado: ${MOD}"
        else
            echo -e "  ${YEL}AVISO: No existe en el save${RST} (tile no explorado)"
        fi
        ;;

    recent)
        MINUTES="${1:-60}"
        print_header
        echo -e "  Chunks modificados en los ultimos ${BLD}${MINUTES} minutos${RST}:"
        echo -e "  ${DIM}(Usalo justo despues de construir algo para identificar tu base)${RST}"
        echo ""
        COUNT=0
        while IFS= read -r chunk_file; do
            CX=$(basename "$(dirname "$chunk_file")")
            CY=$(basename "$chunk_file" .bin)
            TILE_X=$((CX * 10))
            TILE_Y=$((CY * 10))
            MOD=$(date -r "$chunk_file" "+%H:%M:%S")
            SIZE=$(du -sh "$chunk_file" | cut -f1)
            echo -e "  ${MAG}map/${CX}/${CY}.bin${RST}  tiles(${TILE_X}-$((TILE_X+9)), ${TILE_Y}-$((TILE_Y+9)))  ${SIZE}  mod:${MOD}"
            ((COUNT++)) || true
        done < <(find "${SAVE_DIR}/map" -name "*.bin" -mmin -"${MINUTES}" | sort -t/ -k1,1n -k2,2n 2>/dev/null)

        if [[ $COUNT -eq 0 ]]; then
            echo -e "  ${YEL}No se encontraron chunks modificados en los ultimos ${MINUTES} min.${RST}"
            echo -e "  Prueba con un valor mayor: $0 recent 120"
            echo ""
            echo -e "  ${DIM}Nota: si todos los chunks tienen timestamps similares, el servidor${RST}"
            echo -e "  ${DIM}los genero todos a la vez. Usa 'scan' con coordenadas en ese caso.${RST}"
        else
            echo ""
            echo -e "  Total: ${BLD}${COUNT} chunk(s)${RST} modificados en los ultimos ${MINUTES} min."
            echo ""
            echo -e "  ${GRN}Para preservar estos chunks:${RST}"
            echo -e "  ${CYN}  ~/Zomboid/pz_wipe.sh${RST}"
            echo -e "  ${DIM}  Elige: [3] Selectivo -> [B] Por timestamp${RST}"
            echo -e "  ${DIM}  Ingresa la hora en que empezaste a construir.${RST}"
        fi
        ;;

    scan)
        ZONE="${1:-}"
        if [[ -z "$ZONE" ]]; then
            echo "Uso: $0 scan \"X1,Y1,X2,Y2\""
            echo "Ejemplo: $0 scan \"10200,14500,10280,14580\""
            exit 1
        fi
        IFS=',' read -r TX1 TY1 TX2 TY2 <<< "$ZONE"
        if [[ $TX1 -gt $TX2 ]]; then tmp=$TX1; TX1=$TX2; TX2=$tmp; fi
        if [[ $TY1 -gt $TY2 ]]; then tmp=$TY1; TY1=$TY2; TY2=$tmp; fi
        CX1=$((TX1 / 10)); CY1=$((TY1 / 10))
        CX2=$((TX2 / 10)); CY2=$((TY2 / 10))
        print_header
        echo -e "  Zona tiles: (${TX1},${TY1}) -> (${TX2},${TY2})"
        echo -e "  Rango chunks: (${CX1},${CY1}) -> (${CX2},${CY2})"
        echo ""
        COUNT=0; EXIST=0
        for ((cx = CX1; cx <= CX2; cx++)); do
            for ((cy = CY1; cy <= CY2; cy++)); do
                f="${SAVE_DIR}/map/${cx}/${cy}.bin"
                if [[ -f "$f" ]]; then
                    SIZE=$(du -sh "$f" | cut -f1)
                    echo -e "  ${GRN}OK${RST} map/${cx}/${cy}.bin  (${SIZE})"
                    ((EXIST++)) || true
                else
                    echo -e "  ${YEL}--${RST} map/${cx}/${cy}.bin  (no explorado)"
                fi
                ((COUNT++)) || true
            done
        done
        echo ""
        echo -e "  Total: ${COUNT} chunks en zona | ${EXIST} existentes en save"
        echo ""
        echo -e "  ${GRN}Para preservar esta zona:${RST}"
        echo -e "  ${CYN}  ~/Zomboid/pz_wipe.sh${RST}"
        echo -e "  ${DIM}  Elige: [3] Selectivo -> [A] Por coordenadas${RST}"
        echo -e "  ${DIM}  Ingresa la zona: ${TX1},${TY1},${TX2},${TY2}${RST}"
        ;;

    help|--help|-h|*)
        print_header
        echo -e "  ${DIM}Herramienta auxiliar de pz_wipe.sh${RST}"
        echo -e "  ${DIM}Usala para identificar coordenadas ANTES de un wipe selectivo.${RST}"
        echo ""
        echo -e "  ${BLD}Comandos:${RST}"
        echo ""
        echo -e "  ${CYN}tile  <X> <Y>${RST}"
        echo -e "    Que chunk/archivo corresponde a esas coordenadas de tile."
        echo -e "    Ejemplo: $0 tile 10230 14520"
        echo -e "    ${DIM}(usa las coords que ves en el juego con F11)${RST}"
        echo ""
        echo -e "  ${CYN}chunk <CX> <CY>${RST}"
        echo -e "    Que tiles cubre ese archivo de chunk."
        echo -e "    Ejemplo: $0 chunk 1023 1452"
        echo ""
        echo -e "  ${CYN}recent [minutos]${RST}"
        echo -e "    Chunks modificados en los ultimos N minutos (default: 60)."
        echo -e "    Usalo DESPUES de construir algo para identificar tu base."
        echo -e "    Ejemplo: $0 recent 30"
        echo ""
        echo -e "  ${CYN}scan \"X1,Y1,X2,Y2\"${RST}"
        echo -e "    Todos los chunks dentro de un area de tiles."
        echo -e "    Ejemplo: $0 scan \"10200,14500,10280,14580\""
        echo ""
        echo -e "  ${BLD}Flujo de uso:${RST}"
        echo -e "    1. Construye algo en el juego"
        echo -e "    2. Apaga el servidor"
        echo -e "    3. Corre: ${CYN}$0 recent 60${RST}"
        echo -e "       o:     ${CYN}$0 scan \"X1,Y1,X2,Y2\"${RST}"
        echo -e "    4. Usa las coords en: ${CYN}~/Zomboid/pz_wipe.sh -> Modo 3${RST}"
        echo ""
        ;;
esac
echo ""
