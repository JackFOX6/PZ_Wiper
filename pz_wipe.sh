#!/usr/bin/env bash
# =============================================================================
#  pz_wipe.sh — Project Zomboid Build 42 | Script Maestro de Wipe
#  Versión: 2.0
#
#  PROPÓSITO:
#    Herramienta unificada para limpiar el mundo de un servidor PZ B42,
#    con opciones para wipe completo, parcial, o selectivo por zonas.
#    Siempre respalda antes de tocar nada.
#
#  DESDE DÓNDE EJECUTAR:
#    Este script usa rutas absolutas configuradas abajo.
#    Puedes ejecutarlo desde CUALQUIER directorio del sistema:
#
#      ~/Zomboid/pz_wipe.sh           ← desde tu home
#      /home/j4ck/Zomboid/pz_wipe.sh  ← ruta absoluta (recomendada en VPS)
#      bash ~/Zomboid/pz_wipe.sh      ← invocación explícita con bash
#
#    NO necesitas estar dentro de ~/Zomboid/ para ejecutarlo.
#    NO uses "cd ~/Zomboid && ./pz_wipe.sh" — no hace falta.
#
#  ADAPTAR PARA EL VPS:
#    Solo edita la variable PZ_BASE_DIR en la sección CONFIG abajo.
#    Ejemplo para VPS con usuario steam:  PZ_BASE_DIR="/home/steam/Zomboid"
#    Ejemplo para VPS con root:           PZ_BASE_DIR="/root/Zomboid"
#    Todo lo demás se calcula automáticamente.
#
#  MODOS:
#    [1] Wipe COMPLETO  — borra todo el mapa, preserva jugadores y cuentas
#    [2] Wipe PARCIAL   — igual pero preserva la zona actual de los jugadores
#    [3] Wipe SELECTIVO — preserva chunks específicos (bases construidas)
#    [4] Solo BACKUP    — respalda sin tocar nada
#    [5] ESTADO         — muestra info del save actual
#
#  ARCHIVOS QUE NUNCA SE BORRAN (en ningún modo):
#    • db/servertest.db         → cuentas de usuario, whitelist, roles, bans
#    • players.db               → personajes, skills, inventarios
#    • vehicles.db              → vehículos del mapa
#    • Server/servertest.ini    → configuración del servidor
#    • Server/servertest_SandboxVars.lua → configuración sandbox
#
#  HERRAMIENTA AUXILIAR:
#    Usa pz_coords.sh para identificar coordenadas antes del wipe selectivo:
#      ~/Zomboid/pz_coords.sh tile 10230 14520
#      ~/Zomboid/pz_coords.sh recent 60
#
# =============================================================================

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
#  CONFIGURACIÓN — EDITA ESTAS VARIABLES ANTES DE SUBIR AL VPS
# ════════════════════════════════════════════════════════════════════════════
#
#  PZ_BASE_DIR: Directorio raíz de Zomboid en ESTA máquina.
#
#  Ejemplos:
#    Esta PC (j4ck local):    PZ_BASE_DIR="/home/j4ck/Zomboid"
#    VPS con usuario steam:   PZ_BASE_DIR="/home/steam/Zomboid"
#    VPS con root:            PZ_BASE_DIR="/root/Zomboid"
#    VPS con usuario ubuntu:  PZ_BASE_DIR="/home/ubuntu/Zomboid"
#
PZ_BASE_DIR="/home/j4ck/Zomboid"

#  SERVER_NAME: Nombre exacto del servidor.
#  Debe coincidir con:
#    - El nombre de la carpeta en Saves/Multiplayer/<SERVER_NAME>/
#    - El prefijo de los archivos en Server/<SERVER_NAME>.ini
#
#  Ejemplo: si tienes Server/miservidor.ini → SERVER_NAME="miservidor"
#
SERVER_NAME="servertest"

#  MARGIN_CHUNKS: Margen de chunks alrededor de zonas preservadas.
#  Cada chunk = 10 tiles. Margen de 2 = 20 tiles de buffer.
#  Aumenta si tu base es grande y quieres más seguridad en los bordes.
#
MARGIN_CHUNKS=2

# ════════════════════════════════════════════════════════════════════════════
#  RUTAS DERIVADAS — No editar (se calculan desde CONFIG)
# ════════════════════════════════════════════════════════════════════════════
SAVE_DIR="${PZ_BASE_DIR}/Saves/Multiplayer/${SERVER_NAME}"
SERVER_CONFIG_DIR="${PZ_BASE_DIR}/Server"
DB_DIR="${PZ_BASE_DIR}/db"
BACKUP_BASE="${PZ_BASE_DIR}/backups"

# Archivos de configuración del servidor (se respaldan, nunca se borran)
SERVER_INI="${SERVER_CONFIG_DIR}/${SERVER_NAME}.ini"
SERVER_SANDBOX="${SERVER_CONFIG_DIR}/${SERVER_NAME}_SandboxVars.lua"
SERVER_SPAWNPOINTS="${SERVER_CONFIG_DIR}/${SERVER_NAME}_spawnpoints.lua"
SERVER_SPAWNREGIONS="${SERVER_CONFIG_DIR}/${SERVER_NAME}_spawnregions.lua"

# Base de datos de usuarios/cuentas (se respalda, NUNCA se borra)
USERS_DB="${DB_DIR}/${SERVER_NAME}.db"

# ════════════════════════════════════════════════════════════════════════════
#  COLORES Y UTILIDADES
# ════════════════════════════════════════════════════════════════════════════
RED='\033[0;31m'; YEL='\033[1;33m'; GRN='\033[0;32m'
CYN='\033[0;36m'; MAG='\033[0;35m'; BLD='\033[1m'; RST='\033[0m'
DIM='\033[2m'

log_info()    { echo -e "${CYN}[INFO]${RST}  $*"; }
log_ok()      { echo -e "${GRN}[OK]${RST}    $*"; }
log_warn()    { echo -e "${YEL}[WARN]${RST}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RST} $*" >&2; }
log_keep()    { echo -e "${MAG}[KEEP]${RST}  $*"; }
log_delete()  { echo -e "${RED}[BORRAR]${RST} $*"; }
log_never()   { echo -e "${GRN}[SEGURO]${RST} $*"; }

separator()   { echo -e "${DIM}────────────────────────────────────────────────────────${RST}"; }
big_sep()     { echo -e "${BLD}════════════════════════════════════════════════════════${RST}"; }

press_enter() {
    echo ""
    echo -e "${DIM}  Presiona ENTER para continuar...${RST}"
    read -r
}

confirm() {
    local msg="${1:-¿Confirmar?}"
    echo -e "${YEL}${BLD}  ${msg} [s/N]:${RST} " && read -r ans
    [[ "$ans" =~ ^[sS]$ ]]
}

# ════════════════════════════════════════════════════════════════════════════
#  VALIDACIÓN INICIAL DEL ENTORNO
# ════════════════════════════════════════════════════════════════════════════
validate_environment() {
    local errors=0

    echo ""
    log_info "Validando entorno..."

    # Auto-detección inteligente del save si SERVER_NAME por defecto no existe en disco
    if [[ ! -d "$SAVE_DIR" && -d "${PZ_BASE_DIR}/Saves/Multiplayer" ]]; then
        local saves=()
        mapfile -t saves < <(ls -1 "${PZ_BASE_DIR}/Saves/Multiplayer" 2>/dev/null || true)
        if [[ ${#saves[@]} -eq 1 && -n "${saves[0]:-}" ]]; then
            SERVER_NAME="${saves[0]}"
            SAVE_DIR="${PZ_BASE_DIR}/Saves/Multiplayer/${SERVER_NAME}"
            SERVER_INI="${SERVER_CONFIG_DIR}/${SERVER_NAME}.ini"
            SERVER_SANDBOX="${SERVER_CONFIG_DIR}/${SERVER_NAME}_SandboxVars.lua"
            SERVER_SPAWNPOINTS="${SERVER_CONFIG_DIR}/${SERVER_NAME}_spawnpoints.lua"
            SERVER_SPAWNREGIONS="${SERVER_CONFIG_DIR}/${SERVER_NAME}_spawnregions.lua"
            USERS_DB="${DB_DIR}/${SERVER_NAME}.db"
            log_info "Auto-detectado único servidor save en disco: ${BLD}${SERVER_NAME}${RST}"
        fi
    fi

    # Verificar directorio base
    if [[ ! -d "$PZ_BASE_DIR" ]]; then
        log_error "PZ_BASE_DIR no existe: ${BLD}${PZ_BASE_DIR}${RST}"
        log_error "Edita la variable PZ_BASE_DIR en este script."
        log_error "Ejemplo VPS steam: PZ_BASE_DIR=\"/home/steam/Zomboid\""
        ((errors++))
    fi

    # Verificar directorio del save
    if [[ ! -d "$SAVE_DIR" ]]; then
        log_error "Directorio del save no encontrado: ${BLD}${SAVE_DIR}${RST}"
        log_error "Verifica que SERVER_NAME='${SERVER_NAME}' sea correcto."
        log_error "Carpetas disponibles en Saves/Multiplayer/:"
        ls "${PZ_BASE_DIR}/Saves/Multiplayer/" 2>/dev/null | sed 's/^/    /' || true
        ((errors++))
    fi

    # Verificar mapa o players.db (save válido)
    if [[ ! -f "${SAVE_DIR}/players.db" ]]; then
        if [[ -d "${SAVE_DIR}/map" ]]; then
            log_warn "players.db no encontrado en el save, pero carpeta map/ existe (servidor recién creado o sin usuarios activos)."
        else
            log_error "players.db ni carpeta map/ encontrados en el save: ${SAVE_DIR}"
            log_error "El servidor debe haberse ejecutado al menos una vez para generar el mapa."
            ((errors++))
        fi
    fi

    # Verificar directorio de config
    if [[ ! -d "$SERVER_CONFIG_DIR" ]]; then
        log_warn "Directorio Server/ no encontrado: ${SERVER_CONFIG_DIR}"
        log_warn "Los configs no serán incluidos en el backup."
    fi

    # Verificar db de usuarios
    if [[ ! -f "$USERS_DB" ]]; then
        log_warn "Base de datos de usuarios no encontrada: ${USERS_DB}"
        log_warn "Si tu servidor usa whitelist, esto puede ser un problema."
    fi

    if [[ $errors -gt 0 ]]; then
        echo ""
        log_error "${errors} error(s) crítico(s). Corrige la configuración y vuelve a ejecutar."
        exit 1
    fi

    log_ok "Entorno validado correctamente."
}

# ════════════════════════════════════════════════════════════════════════════
#  VALIDACIÓN DE INTEGRIDAD DE SANDBOXVARS (MODS)
# ════════════════════════════════════════════════════════════════════════════
validate_sandbox_completeness() {
    local file="${SERVER_SANDBOX}"
    [[ ! -f "$file" ]] && return 0

    local line_count=0
    line_count=$(wc -l < "$file" 2>/dev/null || echo 0)
    
    local -a missing_keywords=()
    for kw in "WDecay" "workingSeatbelt" "BetterSafehouse" "RestoreUtilities"; do
        if ! grep -q "$kw" "$file" 2>/dev/null; then
            missing_keywords+=("$kw")
        fi
    done

    local is_incomplete=false
    if [[ $line_count -lt 1100 ]]; then
        is_incomplete=true
    fi
    if [[ ${#missing_keywords[@]} -gt 0 ]]; then
        is_incomplete=true
    fi

    if $is_incomplete; then
        echo ""
        log_warn "⚠️ DETECTADA CONFIGURACIÓN SANDBOX INCOMPLETA"
        log_warn "El archivo SandboxVars.lua actual parece ser vanilla o le faltan mods."
        log_warn "  • Líneas en archivo: ${line_count} (Mínimo recomendado para mods: 1100)"
        if [[ ${#missing_keywords[@]} -gt 0 ]]; then
            log_warn "  • Bloques de mods faltantes: [ ${missing_keywords[*]} ]"
        fi
        echo ""
        log_warn "Si realizas el wipe ahora, la copia de seguridad que se guardará"
        log_warn "no tendrá las variables de tus mods."
        echo ""
        if ! confirm "¿Deseas proceder con el backup/wipe a pesar de esto?"; then
            log_error "Operación cancelada por el usuario."
            press_enter
            return 1
        fi
    fi
    return 0
}

# ════════════════════════════════════════════════════════════════════════════
#  BACKUP UNIVERSAL
#  Siempre se ejecuta antes de cualquier wipe.
#  Respalda: save/ + config/ + db/
# ════════════════════════════════════════════════════════════════════════════
do_backup() {
    # Validar integridad del sandbox antes de respaldar
    validate_sandbox_completeness || return 1

    local tipo="${1:-wipe}"
    local TIMESTAMP
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local BACKUP_PATH="${BACKUP_BASE}/${SERVER_NAME}_${tipo}_${TIMESTAMP}"

    echo ""
    separator
    echo -e "${BLD}  BACKUP${RST}"
    separator
    log_info "Creando backup en:"
    echo -e "  ${BLD}${BACKUP_PATH}${RST}"
    echo ""

    mkdir -p "${BACKUP_PATH}"

    # 1. Save del mundo
    if [[ -d "$SAVE_DIR" ]]; then
        log_info "Respaldando save del mundo..."
        cp -a "$SAVE_DIR" "${BACKUP_PATH}/save/"
        local save_size
        save_size=$(du -sh "${BACKUP_PATH}/save/" | cut -f1)
        log_ok "Save respaldado (${save_size})"
    fi

    # 2. Configuración del servidor
    if [[ -d "$SERVER_CONFIG_DIR" ]]; then
        log_info "Respaldando configuración del servidor (Server/)..."
        mkdir -p "${BACKUP_PATH}/config/"
        for f in "${SERVER_INI}" "${SERVER_SANDBOX}" "${SERVER_SPAWNPOINTS}" "${SERVER_SPAWNREGIONS}"; do
            [[ -f "$f" ]] && cp "$f" "${BACKUP_PATH}/config/" && log_ok "  $(basename "$f")"
        done
        # También copiar ssr.ini si existe
        [[ -f "${SERVER_CONFIG_DIR}/ssr.ini" ]] && cp "${SERVER_CONFIG_DIR}/ssr.ini" "${BACKUP_PATH}/config/"
    fi

    # 3. Base de datos de usuarios
    if [[ -f "$USERS_DB" ]]; then
        log_info "Respaldando base de datos de usuarios (db/)..."
        mkdir -p "${BACKUP_PATH}/db/"
        cp "${USERS_DB}" "${BACKUP_PATH}/db/"
        [[ -f "${USERS_DB}-journal" ]] && cp "${USERS_DB}-journal" "${BACKUP_PATH}/db/" 2>/dev/null || true
        local db_size
        db_size=$(du -sh "${BACKUP_PATH}/db/" | cut -f1)
        log_ok "DB usuarios respaldada (${db_size})"
    fi

    local total_size
    total_size=$(du -sh "${BACKUP_PATH}" | cut -f1)
    echo ""
    log_ok "Backup completo: ${BLD}${total_size}${RST} total"
    log_ok "Ubicación: ${BLD}${BACKUP_PATH}${RST}"

    LAST_BACKUP_PATH="$BACKUP_PATH"
}

# ════════════════════════════════════════════════════════════════════════════
#  FUNCIONES DE BORRADO (con soporte DRY_RUN)
# ════════════════════════════════════════════════════════════════════════════
DRY_RUN=false

wipe_file() {
    local file="$1" label="${2:-$(basename "$1")}"
    [[ ! -f "$file" ]] && { log_warn "No encontrado (ok): $label"; return; }
    if $DRY_RUN; then
        local sz; sz=$(du -sh "$file" 2>/dev/null | cut -f1)
        echo -e "  ${YEL}[DRY]${RST} Borraría (${sz}): ${label}"
    else
        rm -f "$file"
        log_ok "Borrado: $label"
    fi
}

wipe_dir() {
    local dir="$1" label="${2:-$1}"
    [[ ! -d "$dir" ]] && { log_warn "No encontrado (ok): $label"; return; }
    local count; count=$(find "$dir" -type f | wc -l)
    if $DRY_RUN; then
        echo -e "  ${YEL}[DRY]${RST} Borraría ${count} archivo(s): ${label}"
    else
        rm -rf "$dir"; mkdir -p "$dir"
        log_ok "Limpiado ($count archivos): $label"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
#  NÚCLEO: BORRAR ARCHIVOS DE ESTADO DEL MUNDO
#  (igual en todos los modos de wipe)
# ════════════════════════════════════════════════════════════════════════════
wipe_world_state() {
    local preserve_meta="${1:-false}"
    local preserve_visited="${2:-false}"
    local preserve_zpop_selective="${3:-false}"
    local preserve_cdata_selective="${4:-false}"
    echo ""
    echo -e "${BLD}  Limpiando estado del mundo (Build 42)...${RST}"

    # Directorios de datos de mapa (derivados)
    wipe_dir  "${SAVE_DIR}/isoregiondata"       "isoregiondata/"
    wipe_dir  "${SAVE_DIR}/vehicle_data"        "vehicle_data/"
    
    if [[ "$preserve_cdata_selective" == "true" ]]; then
        log_keep "chunkdata/ — PRESERVACIÓN SELECTIVA (evita reinicio de tiempo invisible)"
    else
        wipe_dir  "${SAVE_DIR}/chunkdata"            "chunkdata/"
    fi
    
    if [[ "$preserve_zpop_selective" == "true" ]]; then
        log_keep "zpop/ — PRESERVACIÓN SELECTIVA (evita zombies en bases)"
    else
        wipe_dir  "${SAVE_DIR}/zpop"                 "zpop/ (población zombie)"
    fi
    
    wipe_dir  "${SAVE_DIR}/apop"                 "apop/ (animales)"
    wipe_dir  "${SAVE_DIR}/metagrid"             "metagrid/"
    
    if [[ "$preserve_visited" == "true" ]]; then
        log_keep "map_visited_server/ — PRESERVADO (modo parcial)"
    else
        wipe_dir  "${SAVE_DIR}/map_visited_server"   "map_visited_server/"
    fi
    
    wipe_dir  "${SAVE_DIR}/radio"                "radio/"

    # Archivos binarios de estado del mundo
    if [[ "$preserve_meta" == "true" ]]; then
        log_keep "map_meta.bin — PRESERVADO (evita reset de SandboxVars)"
        log_keep "map_t.bin — PRESERVADO (evita desajuste del reloj)"
    else
        wipe_file "${SAVE_DIR}/map_meta.bin"         "map_meta.bin"
        wipe_file "${SAVE_DIR}/map_t.bin"            "map_t.bin (clima/tiempo)"
    fi
    
    wipe_file "${SAVE_DIR}/map_zone.bin"         "map_zone.bin"
    wipe_file "${SAVE_DIR}/map_worldgen.bin"     "map_worldgen.bin"
    wipe_file "${SAVE_DIR}/map_animals.bin"      "map_animals.bin"
    wipe_file "${SAVE_DIR}/map_basements.bin"    "map_basements.bin"
    wipe_file "${SAVE_DIR}/map_fluid.bin"        "map_fluid.bin (fluidos B42)"
    wipe_file "${SAVE_DIR}/map_movables.bin"     "map_movables.bin (muebles B42)"
    wipe_file "${SAVE_DIR}/map_electricity.bin"  "map_electricity.bin (red eléctrica B42)"
    wipe_file "${SAVE_DIR}/map_water.bin"        "map_water.bin (red de agua B42)"
    wipe_file "${SAVE_DIR}/map_farming.bin"      "map_farming.bin (cultivos B42)"
    wipe_file "${SAVE_DIR}/heat_map.bin"         "heat_map.bin (mapa de calor/sonido B42)"
    wipe_file "${SAVE_DIR}/erosion.ini"          "erosion.ini"
    wipe_file "${SAVE_DIR}/reanimated.bin"       "reanimated.bin"
    wipe_file "${SAVE_DIR}/z_outfits.bin"        "z_outfits.bin"
    wipe_file "${SAVE_DIR}/iTrack.bin"           "iTrack.bin (loot tracker)"
    wipe_file "${SAVE_DIR}/servermap_symbols.bin" "servermap_symbols.bin"
    wipe_file "${SAVE_DIR}/important_area_data.bin" "important_area_data.bin"

    # Wildcards para subarchivos de metadatos del mapa B42
    for meta_sub in "${SAVE_DIR}"/map_meta_*.bin; do
        [[ -f "$meta_sub" ]] && wipe_file "$meta_sub" "$(basename "$meta_sub")"
    done

    # Game Object Systems
    for gos_file in "${SAVE_DIR}"/gos_*.bin; do
        [[ -f "$gos_file" ]] && wipe_file "$gos_file" "$(basename "$gos_file")"
    done
}

verify_protected_files() {
    echo ""
    echo -e "${BLD}  Verificando archivos protegidos (NUNCA se borran)...${RST}"
    log_never "db/${SERVER_NAME}.db (cuentas/whitelist): $(du -sh "$USERS_DB" 2>/dev/null | cut -f1 || echo 'no encontrado')"
    log_never "players.db: $(du -sh "${SAVE_DIR}/players.db" 2>/dev/null | cut -f1 || echo 'no encontrado')"
    log_never "vehicles.db: $(du -sh "${SAVE_DIR}/vehicles.db" 2>/dev/null | cut -f1 || echo 'no encontrado')"
    log_never "Server/${SERVER_NAME}.ini: $(du -sh "$SERVER_INI" 2>/dev/null | cut -f1 || echo 'no encontrado')"
    log_never "Server/${SERVER_NAME}_SandboxVars.lua: $(du -sh "$SERVER_SANDBOX" 2>/dev/null | cut -f1 || echo 'no encontrado')"
}

# ════════════════════════════════════════════════════════════════════════════
#  MODO 1: WIPE COMPLETO
# ════════════════════════════════════════════════════════════════════════════
mode_wipe_completo() {
    echo ""
    big_sep
    echo -e "${BLD}  MODO 1 — WIPE COMPLETO${RST}"
    big_sep
    echo ""
    echo -e "  Borrará ${RED}${BLD}TODO${RST} el mapa del mundo."
    echo ""
    echo -e "  ${GRN}PRESERVA (nunca toca):${RST}"
    echo -e "    • db/${SERVER_NAME}.db          → cuentas, whitelist, roles, bans"
    echo -e "    • players.db                → personajes, skills, inventarios"
    echo -e "    • vehicles.db               → vehículos de todos los jugadores"
    echo -e "    • Server/ (configs)         → servertest.ini, SandboxVars.lua"
    echo ""
    echo -e "  ${RED}BORRARÁ:${RST}"
    local chunk_count
    chunk_count=$(find "${SAVE_DIR}/map" -name "*.bin" 2>/dev/null | wc -l)
    echo -e "    • ${chunk_count} chunks del mapa (map/)"
    echo -e "    • isoregiondata, chunkdata, zpop, apop, metagrid"
    echo -e "    • map_meta.bin, map_t.bin, map_zone.bin y otros binarios de estado"
    echo ""
    echo -e "  ${YEL}RESULTADO:${RST} El mundo se regenerará desde cero al iniciar el servidor."
    echo -e "  Los jugadores conservarán personajes y vehículos."
    echo ""
    separator

    if ! confirm "¿Confirmas el WIPE COMPLETO? Esta acción es irreversible sin el backup"; then
        echo "  Cancelado."; return
    fi

    do_backup "completo" || return 1
    verify_protected_files

    echo ""
    echo -e "${BLD}  Borrando chunks del mapa...${RST}"
    wipe_dir "${SAVE_DIR}/map" "map/ (${chunk_count} chunks)"
    wipe_world_state

    if ! $DRY_RUN; then
        print_success_summary "completo"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
#  MODO 2: WIPE PARCIAL
# ════════════════════════════════════════════════════════════════════════════
mode_wipe_parcial() {
    echo ""
    big_sep
    echo -e "${BLD}  MODO 2 — WIPE PARCIAL${RST}"
    big_sep
    echo ""
    echo -e "  Igual que el completo, pero PRESERVA el registro de"
    echo -e "  zonas visitadas (${BLD}map_visited_server/${RST})."
    echo ""
    echo -e "  ${CYN}¿Cuándo usar esto?${RST}"
    echo -e "  Cuando hay jugadores en el servidor y no quieres que"
    echo -e "  pierdan su historial de exploración de zonas."
    echo -e "  Los chunks del mapa se resetean igual."
    echo ""
    echo -e "  ${GRN}PRESERVA (además de los siempre protegidos):${RST}"
    echo -e "    • map_visited_server/  → historial de zonas exploradas"
    echo ""
    separator

    if ! confirm "¿Confirmas el WIPE PARCIAL?"; then
        echo "  Cancelado."; return
    fi

    do_backup "parcial" || return 1
    verify_protected_files

    local chunk_count
    chunk_count=$(find "${SAVE_DIR}/map" -name "*.bin" 2>/dev/null | wc -l)
    echo ""
    echo -e "${BLD}  Borrando chunks del mapa...${RST}"
    wipe_dir "${SAVE_DIR}/map" "map/ (${chunk_count} chunks)"

    # Wipe de estado del mundo preservando map_meta y map_visited_server
    wipe_world_state "true" "true"

    if ! $DRY_RUN; then
        print_success_summary "parcial"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
#  MODO 3: WIPE SELECTIVO
# ════════════════════════════════════════════════════════════════════════════
declare -a PROTECTED_CHUNKS=()
declare -a ZONE_MAPS=()

render_ascii_map_for_zone() {
    local name="$1"
    local -i scx1="$2"
    local -i scy1="$3"
    local -i scx2="$4"
    local -i scy2="$5"
    
    # Añadimos un borde de 2 chunks alrededor para ver el límite del borrado
    local -i min_x=$((scx1 - 2))
    local -i max_x=$((scx2 + 2))
    local -i min_y=$((scy1 - 2))
    local -i max_y=$((scy2 + 2))
    
    echo -e "  ${BLD}Mapa de protección para: ${YEL}${name}${RST} (Vista de Chunks B42)"
    echo -e "  Leyenda: ${GRN}■${RST} = Protegido | ${RED}·${RST} = Se Borrará"
    echo ""
    
    # Encabezado de columnas (e.g. 50 51 52)
    echo -ne "       "
    for ((x=min_x; x<=max_x; x++)); do
        local val=$((x % 100))
        if [[ $val -lt 0 ]]; then val=$((val * -1)); fi
        printf " %02d" $val
    done
    echo ""
    
    # Filas
    for ((y=min_y; y<=max_y; y++)); do
        printf "  %04d " "$y"
        for ((x=min_x; x<=max_x; x++)); do
            if is_protected "$x" "$y"; then
                echo -ne " ${GRN}■${RST} "
            else
                echo -ne " ${RED}·${RST} "
            fi
        done
        echo ""
    done
    echo ""
}

build_protected_set_from_zones() {
    local -a zones=("$@")
    PROTECTED_CHUNKS=()
    ZONE_MAPS=()
    local count=1
    for zone in "${zones[@]}"; do
        IFS=',' read -r tx1 ty1 tx2 ty2 <<< "$zone"
        if [[ $tx1 -gt $tx2 ]]; then local t=$tx1; tx1=$tx2; tx2=$t; fi
        if [[ $ty1 -gt $ty2 ]]; then local t=$ty1; ty1=$ty2; ty2=$t; fi
        local cx1=$(( tx1/10 - MARGIN_CHUNKS ))
        local cy1=$(( ty1/10 - MARGIN_CHUNKS ))
        local cx2=$(( tx2/10 + MARGIN_CHUNKS ))
        local cy2=$(( ty2/10 + MARGIN_CHUNKS ))
        ZONE_MAPS+=("Zona Manual #${count}:${cx1}:${cy1}:${cx2}:${cy2}")
        ((count++)) || true
        log_info "  Zona (${tx1},${ty1})→(${tx2},${ty2}) | Chunks (${cx1},${cy1})→(${cx2},${cy2}) | Margen: ${MARGIN_CHUNKS}"
        for ((cx=cx1; cx<=cx2; cx++)); do
            for ((cy=cy1; cy<=cy2; cy++)); do
                PROTECTED_CHUNKS+=("${cx}:${cy}")
            done
        done
    done
    mapfile -t PROTECTED_CHUNKS < <(printf '%s\n' "${PROTECTED_CHUNKS[@]}" | sort -u)
}

build_protected_set_from_zones_append() {
    local -a zones=("$@")
    local count=1
    for zone in "${zones[@]}"; do
        IFS=',' read -r tx1 ty1 tx2 ty2 <<< "$zone"
        if [[ $tx1 -gt $tx2 ]]; then local t=$tx1; tx1=$tx2; tx2=$t; fi
        if [[ $ty1 -gt $ty2 ]]; then local t=$ty1; ty1=$ty2; ty2=$t; fi
        local cx1=$(( tx1/10 - MARGIN_CHUNKS ))
        local cy1=$(( ty1/10 - MARGIN_CHUNKS ))
        local cx2=$(( tx2/10 + MARGIN_CHUNKS ))
        local cy2=$(( ty2/10 + MARGIN_CHUNKS ))
        ZONE_MAPS+=("Zona Manual Anexa #${count}:${cx1}:${cy1}:${cx2}:${cy2}")
        ((count++)) || true
        log_info "  [ANEXO MANUAL] Zona (${tx1},${ty1})→(${tx2},${ty2}) | Chunks (${cx1},${cy1})→(${cx2},${cy2})"
        for ((cx=cx1; cx<=cx2; cx++)); do
            for ((cy=cy1; cy<=cy2; cy++)); do
                PROTECTED_CHUNKS+=("${cx}:${cy}")
            done
        done
    done
    mapfile -t PROTECTED_CHUNKS < <(printf '%s\n' "${PROTECTED_CHUNKS[@]}" | sort -u)
}

build_protected_set_from_timestamp() {
    local since_str="$1"
    local since_epoch
    since_epoch=$(date -d "$since_str" +%s 2>/dev/null) || {
        log_error "Formato de fecha inválido: '${since_str}'"
        log_error "Usa formato: YYYY-MM-DD HH:MM:SS  (ej: 2026-07-04 18:30:00)"
        return 1
    }
    local ts_count=0
    while IFS= read -r chunk_file; do
        local file_ts; file_ts=$(stat -c %Y "$chunk_file")
        if [[ $file_ts -gt $since_epoch ]]; then
            local cy_tmp="${chunk_file##*/}"
            local cy="${cy_tmp%.bin}"
            local cx_path="${chunk_file%/*}"
            local cx="${cx_path##*/}"
            for ((dcx=-MARGIN_CHUNKS; dcx<=MARGIN_CHUNKS; dcx++)); do
                for ((dcy=-MARGIN_CHUNKS; dcy<=MARGIN_CHUNKS; dcy++)); do
                    PROTECTED_CHUNKS+=("$((cx+dcx)):$((cy+dcy))")
                done
            done
            ((ts_count++)) || true
        fi
    done < <(find "${SAVE_DIR}/map" -name "*.bin")
    mapfile -t PROTECTED_CHUNKS < <(printf '%s\n' "${PROTECTED_CHUNKS[@]}" | sort -u)
    log_info "  Chunks detectados por timestamp: ${ts_count} (+ margen ${MARGIN_CHUNKS})"
}

is_protected() {
    local key="${1}:${2}"
    [[ -n "${PROTECTED_MAP[$key]:-}" ]] && return 0 || return 1
}

do_selective_wipe() {
    local total_chunks kept_count=0 delete_count=0
    local current_count=0

    # Inicializar mapa de búsqueda O(1) para evitar bucles pesados en Bash
    declare -g -A PROTECTED_MAP=()
    for entry in "${PROTECTED_CHUNKS[@]:-}"; do
        PROTECTED_MAP["$entry"]=1
    done

    total_chunks=$(find "${SAVE_DIR}/map" -name "*.bin" | wc -l)

    # Contar cuántos chunks existentes están protegidos
    for entry in "${PROTECTED_CHUNKS[@]:-}"; do
        IFS=':' read -r cx cy <<< "$entry"
        [[ -f "${SAVE_DIR}/map/${cx}/${cy}.bin" ]] && ((kept_count++)) || true
    done
    delete_count=$((total_chunks - kept_count))

    # Verificación anti-error: si 0 chunks protegidos existen
    if [[ $kept_count -eq 0 ]]; then
        echo ""
        log_warn "ALERTA: No se encontró físicamente NINGÚN chunk de los protegidos en tu disco."
        log_warn "Esto significa que las zonas de los Safehouses/Jugadores no han sido visitadas o ya fueron borradas."
        log_warn "Si continúas, se realizará un WIPE COMPLETO de los ${total_chunks} chunks existentes."
        echo ""
        if ! confirm "¿Estás completamente seguro de continuar y borrar TODO?"; then
            echo "  Operación cancelada para prevenir pérdida de datos."
            return 1
        fi
    fi

    # Verificación anti-error: si >80% a preservar → advertir
    local pct_keep=$(( kept_count * 100 / total_chunks ))
    if [[ $pct_keep -gt 80 ]]; then
        echo ""
        log_warn "ADVERTENCIA: Estás preservando el ${pct_keep}% del mapa (${kept_count}/${total_chunks} chunks)."
        log_warn "Solo se borrarán ${delete_count} chunks."
        log_warn "¿Seguro que no querías un wipe completo en su lugar?"
        echo ""
        if ! confirm "¿Continuar de todas formas?"; then
            echo "  Operación cancelada."; return 0
        fi
    fi

    echo ""
    echo -e "  Total de chunks: ${BLD}${total_chunks}${RST}"
    echo -e "  ${GRN}Preservar:${RST} ${kept_count} chunks"
    echo -e "  ${RED}Borrar:${RST}    ${delete_count} chunks"
    echo ""

    # Generar mapas visuales ASCII en 2D para cada zona (siempre se muestra, pero resalta en DRY-RUN)
    if [[ ${#ZONE_MAPS[@]} -gt 0 ]]; then
        echo ""
        separator
        echo -e "  ${BLD}VISTA PREVIA DE LAS ZONAS PROTEGIDAS (ASCII MAPS)${RST}"
        separator
        echo ""
        for zone_info in "${ZONE_MAPS[@]}"; do
            IFS=':' read -r zname zcx1 zcy1 zcx2 zcy2 <<< "$zone_info"
            render_ascii_map_for_zone "$zname" "$zcx1" "$zcy1" "$zcx2" "$zcy2"
        done
        separator
        echo ""
    fi

    if ! confirm "¿Confirmar wipe SELECTIVO? Backup ya fue creado"; then
        echo "  Cancelado."; return 0
    fi

    # Archivo temporal seguro para almacenar la cola de borrado masivo
    local delete_queue
    delete_queue=$(mktemp)

    echo ""
    log_info "Analizando mapa y preparando cola de eliminación..."

    # Ejecución del escaneo chunk por chunk con indicador en tiempo real
    while IFS= read -r chunk_file; do
        ((current_count++)) || true
        
        # Actualizar indicador visual cada 200 archivos para no ahogar la terminal
        if (( current_count % 200 == 0 || current_count == total_chunks )); then
            echo -ne "\r  ${CYN}[PROGRESO]${RST} Escaneando: ${BLD}${current_count}${RST}/${total_chunks} chunks..."
        fi

        local cy_tmp="${chunk_file##*/}"
        local cy="${cy_tmp%.bin}"
        local cx_path="${chunk_file%/*}"
        local cx="${cx_path##*/}"
        
        if ! is_protected "$cx" "$cy"; then
            if $DRY_RUN; then
                echo -e "\n  ${YEL}[DRY]${RST} Borraría: map/${cx}/${cy}.bin"
            else
                # En lugar de ejecutar rm aquí, lo mandamos a la cola estática
                echo "$chunk_file" >> "$delete_queue"
            fi
        fi
    done < <(find "${SAVE_DIR}/map" -name "*.bin" | sort)
    
    echo -e " ${GRN}¡Listo!${RST}"

    # Ejecutar la eliminación masiva (Batching) si hay elementos en la cola y no es DRY_RUN
    if [[ -s "$delete_queue" ]] && ! $DRY_RUN; then
        echo ""
        log_info "Ejecutando borrado atómico de ${RED}${delete_count}${RST} archivos..."
        
        # xargs divide automáticamente la lista para no romper el límite de argumentos (ARG_MAX)
        xargs rm -f < "$delete_queue"
        
        log_ok "Borrado masivo completado exitosamente."
    fi

    # Limpieza del archivo temporal de la cola
    rm -f "$delete_queue"

    # Limpiar subdirectorios vacíos
    if ! $DRY_RUN; then
        echo ""
        log_info "Limpiando directorios de coordenadas vacíos..."
        find "${SAVE_DIR}/map" -type d -empty -delete 2>/dev/null || true
    fi

    # Borrado selectivo de zpop/ (población zombie) para evitar spawnkill en bases
    local zpop_dir="${SAVE_DIR}/zpop"
    local deleted_zpop=0
    if [[ -d "$zpop_dir" ]]; then
        # Construir mapa de celdas protegidas para búsqueda O(1)
        declare -A PROTECTED_CELLS=()
        for entry in "${PROTECTED_CHUNKS[@]:-}"; do
            IFS=':' read -r cx cy <<< "$entry"
            local cell_x=$(( cx / 30 ))
            local cell_y=$(( cy / 30 ))
            PROTECTED_CELLS["${cell_x}_${cell_y}"]=1
        done

        # Analizar cada zpop_X_Y.bin
        local zpop_queue
        zpop_queue=$(mktemp)
        while IFS= read -r zpop_file; do
            local zfile="${zpop_file##*/}"
            if [[ "$zfile" =~ zpop_([0-9]+)_([0-9]+)\.bin ]]; then
                local zx="${BASH_REMATCH[1]}"
                local zy="${BASH_REMATCH[2]}"
                if [[ -z "${PROTECTED_CELLS["${zx}_${zy}"]:-}" ]]; then
                    echo "$zpop_file" >> "$zpop_queue"
                    ((deleted_zpop++)) || true
                fi
            fi
        done < <(find "$zpop_dir" -name "zpop_*.bin" 2>/dev/null)

        if [[ -s "$zpop_queue" ]]; then
            if ! $DRY_RUN; then
                xargs rm -f < "$zpop_queue"
                log_ok "Limpieza selectiva de zpop/ completada: se borraron ${deleted_zpop} archivos de población zombie."
            else
                log_info "  [DRY] Borraría ${deleted_zpop} archivos de población zombie (zpop/)"
            fi
        fi
        rm -f "$zpop_queue"
    fi

    # Borrado selectivo de chunkdata/ para evitar que se reseteen los contadores de visita
    local cdata_dir="${SAVE_DIR}/chunkdata"
    local deleted_cdata=0
    if [[ -d "$cdata_dir" ]]; then
        local cdata_queue
        cdata_queue=$(mktemp)
        while IFS= read -r cdata_file; do
            local cfile="${cdata_file##*/}"
            if [[ "$cfile" =~ chunkdata_([0-9]+)_([0-9]+)\.bin ]]; then
                local cx="${BASH_REMATCH[1]}"
                local cy="${BASH_REMATCH[2]}"
                if [[ -z "${PROTECTED_CELLS["${cx}_${cy}"]:-}" ]]; then
                    echo "$cdata_file" >> "$cdata_queue"
                    ((deleted_cdata++)) || true
                fi
            fi
        done < <(find "$cdata_dir" -name "chunkdata_*.bin" 2>/dev/null)

        if [[ -s "$cdata_queue" ]]; then
            if ! $DRY_RUN; then
                xargs rm -f < "$cdata_queue"
                log_ok "Limpieza selectiva de chunkdata/ completada: se borraron ${deleted_cdata} archivos de metadatos de chunk."
            else
                log_info "  [DRY] Borraría ${deleted_cdata} archivos de metadatos de chunk (chunkdata/)"
            fi
        fi
        rm -f "$cdata_queue"
    fi

    wipe_world_state "true" "true" "true" "true"
}

# ════════════════════════════════════════════════════════════════════════════
#  NUEVA FUNCIÓN: AUTOMATIZACIÓN DE PROTECCIÓN DESDE DB (ESTILO BUCHOJEFE)
# ════════════════════════════════════════════════════════════════════════════
build_protected_set_from_db() {
    log_info "Extrayendo zonas de protección automática (Safehouses) estáticamente..."
    PROTECTED_CHUNKS=()
    ZONE_MAPS=()
    
    # 1. Detectar Safehouses usando el parser estático en Python
    local parser_script="${PZ_BASE_DIR}/PZ_Wiper/pz_safehouse_parser.py"
    local map_meta="${SAVE_DIR}/map_meta.bin"
    
    if [[ -f "$parser_script" && -f "$map_meta" ]] && command -v python3 &>/dev/null && command -v jq &>/dev/null; then
        log_info "Escaneando refugios (safehouses) registrados en map_meta.bin..."
        
        # Ejecutar python script y capturar la salida JSON
        local json_output
        json_output=$(python3 "$parser_script" "$map_meta" 2>/dev/null || echo '{"safehouses":[]}')
        
        local sh_count
        sh_count=$(echo "$json_output" | jq '.safehouses | length' 2>/dev/null || echo "0")
        
        if [[ "$sh_count" -gt 0 ]]; then
            for (( i=0; i<sh_count; i++ )); do
                local sx sy sw sh owner
                sx=$(echo "$json_output" | jq -r ".safehouses[$i].x")
                sy=$(echo "$json_output" | jq -r ".safehouses[$i].y")
                sw=$(echo "$json_output" | jq -r ".safehouses[$i].w")
                sh=$(echo "$json_output" | jq -r ".safehouses[$i].h")
                owner=$(echo "$json_output" | jq -r ".safehouses[$i].owner")
                
                if [[ -n "$sx" && "$sx" =~ ^[0-9]+$ && -n "$sy" && "$sy" =~ ^[0-9]+$ ]]; then
                    local tx2=$(( sx + sw ))
                    local ty2=$(( sy + sh ))
                    log_ok "  [REFUGIO DETECTADO] Owner: ${owner} | Tiles: (${sx},${sy}) → (${tx2},${ty2})"
                    
                    local cx1=$(( sx/10 - MARGIN_CHUNKS ))
                    local cy1=$(( sy/10 - MARGIN_CHUNKS ))
                    local cx2=$(( tx2/10 + MARGIN_CHUNKS ))
                    local cy2=$(( ty2/10 + MARGIN_CHUNKS ))
                    
                    ZONE_MAPS+=("Refugio (${owner}):${cx1}:${cy1}:${cx2}:${cy2}")
                    
                    for ((cx=cx1; cx<=cx2; cx++)); do
                        for ((cy=cy1; cy<=cy2; cy++)); do
                            PROTECTED_CHUNKS+=("${cx}:${cy}")
                        done
                    done
                fi
            done
        else
            log_warn "  No se detectaron safehouses activos en map_meta.bin."
        fi
    else
        log_warn "  No se encontró pz_safehouse_parser.py, map_meta.bin, jq o python3 no está instalado."
    fi

    # 2. Detectar posiciones de jugadores desde players.db con inspección dinámica de columnas
    local p_db="${SAVE_DIR}/players.db"
    if [[ -f "$p_db" ]] && command -v sqlite3 &>/dev/null; then
        log_info "Escaneando últimas posiciones de jugadores en players.db (con inspección dinámica)..."
        local p_table="networkPlayers"
        if ! sqlite3 "$p_db" "SELECT name FROM sqlite_master WHERE type='table' AND name='networkPlayers';" 2>/dev/null | grep -q "networkPlayers"; then
            if sqlite3 "$p_db" "SELECT name FROM sqlite_master WHERE type='table' AND name='players';" 2>/dev/null | grep -q "players"; then
                p_table="players"
            fi
        fi

        local p_cols
        p_cols=$(sqlite3 "$p_db" "PRAGMA table_info(${p_table});" 2>/dev/null || true)
        local col_px="x" col_py="y" col_puser="username"
        echo "$p_cols" | grep -qi "pos_x" && col_px="pos_x"
        echo "$p_cols" | grep -qi "pos_y" && col_py="pos_y"
        echo "$p_cols" | grep -qi "worldX" && col_px="worldX"
        echo "$p_cols" | grep -qi "worldY" && col_py="worldY"
        echo "$p_cols" | grep -qi "name" && ! echo "$p_cols" | grep -qi "username" && col_puser="name"

        local p_data
        p_data=$(sqlite3 "$p_db" "SELECT ${col_px}, ${col_py}, ${col_puser} FROM ${p_table};" 2>/dev/null || true)
        
        if [[ -n "$p_data" ]]; then
            while IFS='|' read -r px py puser; do
                local pxi=${px%.*}
                local pyi=${py%.*}
                
                if [[ -n "$pxi" && "$pxi" =~ ^-?[0-9]+$ && -n "$pyi" && "$pyi" =~ ^-?[0-9]+$ ]]; then
                    log_ok "  [JUGADOR DETECTADO] '${puser}' en ubicación: (${pxi},${pyi})"
                    
                    local cx1=$(( pxi/10 - MARGIN_CHUNKS ))
                    local cy1=$(( pyi/10 - MARGIN_CHUNKS ))
                    local cx2=$(( pxi/10 + MARGIN_CHUNKS ))
                    local cy2=$(( pyi/10 + MARGIN_CHUNKS ))
                    
                    ZONE_MAPS+=("Jugador (${puser}):${cx1}:${cy1}:${cx2}:${cy2}")
                    
                    for ((cx=cx1; cx<=cx2; cx++)); do
                        for ((cy=cy1; cy<=cy2; cy++)); do
                            PROTECTED_CHUNKS+=("${cx}:${cy}")
                        done
                    done
                fi
            done <<< "$p_data"
        else
            log_warn "  No se encontraron registros de posiciones en ${p_table}."
        fi
    else
        log_warn "  No se encontró players.db o sqlite3 no está disponible."
    fi

    # 3. Detectar vehículos desde vehicles.db con inspección dinámica
    local v_db="${SAVE_DIR}/vehicles.db"
    local vehicle_count=0
    if [[ -f "$v_db" ]] && command -v sqlite3 &>/dev/null; then
        log_info "Escaneando vehículos registrados en vehicles.db (con inspección dinámica)..."
        local v_cols
        v_cols=$(sqlite3 "$v_db" "PRAGMA table_info(vehicles);" 2>/dev/null || true)
        local col_vx="wx" col_vy="wy"
        echo "$v_cols" | grep -qi "worldX" && col_vx="worldX"
        echo "$v_cols" | grep -qi "worldY" && col_vy="worldY"
        echo "$v_cols" | grep -qi "^x|" && col_vx="x"
        echo "$v_cols" | grep -qi "^y|" && col_vy="y"

        local v_data
        v_data=$(sqlite3 "$v_db" "SELECT ${col_vx}, ${col_vy} FROM vehicles;" 2>/dev/null || true)
        
        if [[ -n "$v_data" ]]; then
            while IFS='|' read -r vwx vwy; do
                if [[ -n "$vwx" && "$vwx" =~ ^-?[0-9]+$ && -n "$vwy" && "$vwy" =~ ^-?[0-9]+$ ]]; then
                    ((vehicle_count++)) || true
                    local vcx=$(( vwx / 10 ))
                    local vcy=$(( vwy / 10 ))
                    for ((dcx=-1; dcx<=1; dcx++)); do
                        for ((dcy=-1; dcy<=1; dcy++)); do
                            PROTECTED_CHUNKS+=("$((vcx+dcx)):$((vcy+dcy))")
                        done
                    done
                fi
            done <<< "$v_data"
            log_ok "  [VEHÍCULOS DETECTADOS] ${vehicle_count} vehículos indexados (+ margen 1 chunk)"
        else
            log_warn "  No se encontraron vehículos registrados en vehicles.db."
        fi
    else
        log_warn "  No se encontró vehicles.db o sqlite3 no está disponible."
    fi

    # Eliminar duplicados si se poblaron chunks protegidos
    if [[ ${#PROTECTED_CHUNKS[@]} -gt 0 ]]; then
        mapfile -t PROTECTED_CHUNKS < <(printf '%s\n' "${PROTECTED_CHUNKS[@]}" | sort -u)
        log_info "  Total de chunks protegidos automáticamente: ${BLD}${#PROTECTED_CHUNKS[@]}${RST}"
    fi
}

mode_wipe_selectivo() {
    echo ""
    big_sep
    echo -e "${BLD}  MODO 3 — WIPE SELECTIVO (con preservación de bases)${RST}"
    big_sep
    echo ""
    echo -e "  Preserva chunks específicos del mapa donde tienes bases construidas."
    echo -e "  El resto del mundo se regenera desde cero."
    echo ""
    echo -e "  ${YEL}ANTES DE CONTINUAR:${RST}"
    echo -e "  Necesitas las coordenadas de tu base en tiles (world squares)."
    echo -e "  Obtenerlas en el juego: presiona F11 o mira la barra inferior del mapa."
    echo ""
    echo -e "  Herramienta auxiliar disponible:"
    echo -e "  ${CYN}~/Zomboid/pz_coords.sh tile X Y${RST}         → qué chunk corresponde a ese tile"
    echo -e "  ${CYN}~/Zomboid/pz_coords.sh scan X1,Y1,X2,Y2${RST} → escanear una zona entera"
    echo -e "  ${CYN}~/Zomboid/pz_coords.sh recent 60${RST}         → chunks modificados hace 60 min"
    echo ""
    separator

    while true; do
        echo ""
        echo -e "  ${BLD}Sub-opciones:${RST}"
        echo -e "  ${CYN}[A]${RST} Por coordenadas de tile  (X1,Y1,X2,Y2) — MÁS PRECISO"
        echo -e "  ${CYN}[B]${RST} Por timestamp             (chunks modificados desde una hora)"
        echo -e "  ${CYN}[C]${RST} Combinado                 (A + B juntos)"
        echo -e "  ${CYN}[D]${RST} Abrir pz_coords.sh        (identificar coordenadas primero)"
        echo -e "  ${CYN}[E]${RST} Auto-detección Inteligente (Safehouses + Jugadores Activos) — ESTILO B42_CLEANER"
        echo -e "  ${CYN}[0]${RST} Volver al menú principal"
        echo ""
        echo -ne "  Elige opción: "
        read -r sel

        case "${sel^^}" in

        A)
            echo ""
            echo -e "  ${BLD}Modo A: Por coordenadas de tile${RST}"
            echo ""
            echo -e "  Introduce zonas como: ${CYN}X1,Y1,X2,Y2${RST}"
            echo -e "  Donde X1,Y1 = esquina superior-izquierda de tu base"
            echo -e "        X2,Y2 = esquina inferior-derecha de tu base"
            echo ""
            echo -e "  Ejemplo base pequeña en Muldraugh:"
            echo -e "    ${CYN}10230,14520,10270,14560${RST}"
            echo ""
            echo -e "  Puedes agregar múltiples zonas separadas por espacios o enter."
            echo -e "  Cuando termines, escribe ${BLD}listo${RST} y presiona ENTER."
            echo ""

            local -a zones=()
            while true; do
                echo -ne "  Zona (o 'listo'): "
                read -r -a zona_tokens
                [[ ${#zona_tokens[@]} -eq 0 ]] && break
                
                local stop=false
                for token in "${zona_tokens[@]}"; do
                    if [[ "${token,,}" == "listo" ]]; then
                        stop=true
                        break
                    fi
                    if [[ ! "$token" =~ ^[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]] && [[ ! "$token" =~ ^[0-9]+,[0-9]+$ ]]; then
                        log_warn "Formato inválido: $token. Usa: X1,Y1,X2,Y2 o X,Y"
                    else
                        # Si es X,Y (un punto), lo convertimos a X,Y,X,Y para que el generador de zonas le aplique el margen
                        if [[ "$token" =~ ^[0-9]+,[0-9]+$ ]]; then
                            token="${token},${token}"
                        fi
                        zones+=("$token")
                        log_ok "  Zona agregada: $token"
                    fi
                done
                $stop && break
            done

            if [[ ${#zones[@]} -eq 0 ]]; then
                log_warn "No ingresaste ninguna zona. Operación cancelada."; continue
            fi

            echo ""
            log_info "Calculando chunks a preservar..."
            build_protected_set_from_zones "${zones[@]}"
            echo -e "  Chunks únicos protegidos: ${BLD}${#PROTECTED_CHUNKS[@]}${RST}"

            do_backup "selectivo_A" || continue
            verify_protected_files
            do_selective_wipe || continue

            if ! $DRY_RUN; then
                print_success_summary "selectivo"
            fi
            break
            ;;

        B)
            echo ""
            echo -e "  ${BLD}Modo B: Por timestamp${RST}"
            echo ""
            echo -e "  El script preservará los chunks modificados DESPUÉS de la hora que indiques."
            echo -e "  Úsalo justo después de construir algo: anota la hora en que empezaste a construir."
            echo ""
            echo -e "  Formato: ${CYN}YYYY-MM-DD HH:MM:SS${RST}"
            echo -e "  Ejemplo: ${CYN}2026-07-04 18:30:00${RST}"
            echo ""
            echo -ne "  Hora de inicio de construcción: "
            read -r ts_input

            if [[ -z "$ts_input" ]]; then
                log_warn "No ingresaste una fecha. Cancelado."; continue
            fi

            log_info "Buscando chunks modificados desde '${ts_input}'..."
            build_protected_set_from_timestamp "$ts_input" || continue
            echo -e "  Chunks protegidos (únicos): ${BLD}${#PROTECTED_CHUNKS[@]}${RST}"

            do_backup "selectivo_B" || continue
            verify_protected_files
            do_selective_wipe || continue

            if ! $DRY_RUN; then
                print_success_summary "selectivo"
            fi
            break
            ;;

        C)
            echo ""
            echo -e "  ${BLD}Modo C: Combinado (coordenadas + timestamp)${RST}"
            echo ""
            PROTECTED_CHUNKS=()

            # Coordenadas
            local -a zones=()
            echo -e "  ${CYN}Paso 1/2 — Zonas por coordenadas:${RST}"
            echo -e "  Puedes agregar múltiples zonas separadas por espacios. 'listo' para terminar."
            while true; do
                echo -ne "  Zona (o 'listo'): "
                read -r -a zona_tokens
                [[ ${#zona_tokens[@]} -eq 0 ]] && break
                
                local stop=false
                for token in "${zona_tokens[@]}"; do
                    if [[ "${token,,}" == "listo" ]]; then
                        stop=true
                        break
                    fi
                    if [[ ! "$token" =~ ^[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]] && [[ ! "$token" =~ ^[0-9]+,[0-9]+$ ]]; then
                        log_warn "Formato inválido: $token. Usa: X1,Y1,X2,Y2 o X,Y"
                    else
                        if [[ "$token" =~ ^[0-9]+,[0-9]+$ ]]; then
                            token="${token},${token}"
                        fi
                        zones+=("$token")
                        log_ok "  Zona: $token"
                    fi
                done
                $stop && break
            done
            [[ ${#zones[@]} -gt 0 ]] && build_protected_set_from_zones "${zones[@]}"

            # Timestamp
            echo ""
            echo -e "  ${CYN}Paso 2/2 — Timestamp:${RST}"
            echo -ne "  Hora de inicio de construcción (o ENTER para omitir): "
            read -r ts_input
            [[ -n "$ts_input" ]] && build_protected_set_from_timestamp "$ts_input" || true

            # Dedup combinado
            mapfile -t PROTECTED_CHUNKS < <(printf '%s\n' "${PROTECTED_CHUNKS[@]}" | sort -u)
            echo -e "  Chunks protegidos totales (únicos): ${BLD}${#PROTECTED_CHUNKS[@]}${RST}"

            do_backup "selectivo_C" || continue
            verify_protected_files
            do_selective_wipe || continue

            if ! $DRY_RUN; then
                print_success_summary "selectivo"
            fi
            break
            ;;

        D)
            echo ""
            if [[ -f "${PZ_BASE_DIR}/pz_coords.sh" ]]; then
                bash "${PZ_BASE_DIR}/pz_coords.sh" help
                press_enter
            else
                log_warn "pz_coords.sh no encontrado en: ${PZ_BASE_DIR}/pz_coords.sh"
                log_warn "Asegúrate de que ambos scripts estén en la misma carpeta."
            fi
            ;;

        E)
            echo ""
            echo -e "  ${BLD}Modo E: Auto-detección Inteligente + Manual (Híbrido)${RST}"
            echo ""
            echo -e "  1. Escaneando bases de datos del servidor..."
            build_protected_set_from_db
            
            local auto_count=${#PROTECTED_CHUNKS[@]}
            echo -e "  Chunks detectados automáticamente: ${BLD}${auto_count}${RST}"
            echo ""
            
            if confirm "¿Deseas anexar zonas manuales adicionales para proteger vallas/estructuras externas?"; then
                echo ""
                echo -e "  Introduce zonas manuales como: ${CYN}X1,Y1,X2,Y2${RST} o ${CYN}X,Y${RST}"
                echo -e "  Puedes agregar múltiples zonas separadas por espacios. Escribe ${BLD}listo${RST} al finalizar."
                echo ""
                
                local -a manual_zones=()
                while true; do
                    echo -ne "  Zona manual (o 'listo'): "
                    read -r -a zona_tokens
                    [[ ${#zona_tokens[@]} -eq 0 ]] && break
                    
                    local stop=false
                    for token in "${zona_tokens[@]}"; do
                        if [[ "${token,,}" == "listo" ]]; then
                            stop=true
                            break
                        fi
                        if [[ ! "$token" =~ ^[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]] && [[ ! "$token" =~ ^[0-9]+,[0-9]+$ ]]; then
                            log_warn "Formato inválido: $token. Usa: X1,Y1,X2,Y2 o X,Y"
                        else
                            if [[ "$token" =~ ^[0-9]+,[0-9]+$ ]]; then
                                token="${token},${token}"
                            fi
                            manual_zones+=("$token")
                            log_ok "  Zona manual agregada: $token"
                        fi
                    done
                    $stop && break
                done
                
                if [[ ${#manual_zones[@]} -gt 0 ]]; then
                    # Mantenemos las ya detectadas y construimos las nuevas sobre la misma lista
                    build_protected_set_from_zones_append "${manual_zones[@]}"
                fi
            fi
            
            if [[ ${#PROTECTED_CHUNKS[@]} -eq 0 ]]; then
                log_error "No hay ningún chunk protegido definido. Operación cancelada."
                press_enter
                continue
            fi
            
            local total_protected=${#PROTECTED_CHUNKS[@]}
            local manual_added=$((total_protected - auto_count))
            log_ok "Configuración final: ${BLD}${auto_count}${RST} automáticos + ${BLD}${manual_added}${RST} manuales = ${BLD}${total_protected}${RST} chunks protegidos."
            
            do_backup "selectivo_Auto" || continue
            verify_protected_files
            do_selective_wipe || continue

            if ! $DRY_RUN; then
                print_success_summary "selectivo"
            fi
            break
            ;;

        0)
            return 0
            ;;

        *)
            log_warn "Opción inválida: '${sel}'"
            ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════════════════════
#  MODO 4: SOLO BACKUP
# ════════════════════════════════════════════════════════════════════════════
mode_solo_backup() {
    echo ""
    big_sep
    echo -e "${BLD}  MODO 4 — SOLO BACKUP${RST}"
    big_sep
    echo ""
    echo -e "  Crea un backup completo sin modificar nada."
    echo -e "  Incluye: save del mundo + Server/configs + db/usuarios"
    echo ""

    do_backup "manual"

    echo ""
    log_ok "Backup creado. El save no fue modificado."
}

# ════════════════════════════════════════════════════════════════════════════
#  MODO 5: ESTADO DEL SAVE
# ════════════════════════════════════════════════════════════════════════════
mode_estado() {
    echo ""
    big_sep
    echo -e "${BLD}  MODO 5 — ESTADO ACTUAL DEL SAVE${RST}"
    big_sep
    echo ""

    # Rutas configuradas
    echo -e "  ${BLD}Rutas configuradas:${RST}"
    echo -e "  PZ_BASE_DIR:   ${CYN}${PZ_BASE_DIR}${RST}"
    echo -e "  SAVE_DIR:      ${CYN}${SAVE_DIR}${RST}"
    echo -e "  SERVER_CONFIG: ${CYN}${SERVER_CONFIG_DIR}${RST}"
    echo -e "  DB:            ${CYN}${DB_DIR}${RST}"
    echo -e "  BACKUPS:       ${CYN}${BACKUP_BASE}${RST}"
    echo ""
    separator

    # Mapa
    echo -e "  ${BLD}Mapa del mundo:${RST}"
    if [[ -d "${SAVE_DIR}/map" ]]; then
        local chunk_count chunk_dirs
        chunk_count=$(find "${SAVE_DIR}/map" -name "*.bin" 2>/dev/null | wc -l)
        chunk_dirs=$(ls "${SAVE_DIR}/map" 2>/dev/null | wc -l)
        local map_size; map_size=$(du -sh "${SAVE_DIR}/map" 2>/dev/null | cut -f1)
        echo -e "    Chunks: ${BLD}${chunk_count}${RST} archivos en ${chunk_dirs} subdirectorios (${map_size})"
        local last_mod
        last_mod=$(find "${SAVE_DIR}/map" -name "*.bin" -printf '%T@\n' | sort -rn | head -1)
        if [[ -n "$last_mod" ]]; then
            echo -e "    Último guardado: ${BLD}$(date -d "@${last_mod%.*}" "+%Y-%m-%d %H:%M:%S")${RST}"
        fi
    else
        log_warn "No se encontró carpeta map/"
    fi
    echo ""

    # Jugadores
    echo -e "  ${BLD}Jugadores (players.db):${RST}"
    if [[ -f "${SAVE_DIR}/players.db" ]] && command -v sqlite3 &>/dev/null; then
        sqlite3 "${SAVE_DIR}/players.db" "SELECT username FROM networkPlayers LIMIT 20;" 2>/dev/null | \
            sed 's/^/    • /' || echo -e "    ${DIM}(tabla networkPlayers no encontrada)${RST}"
    elif [[ -f "${SAVE_DIR}/players.db" ]]; then
        echo -e "    $(du -sh "${SAVE_DIR}/players.db" | cut -f1) (sqlite3 no instalado para listar)"
    else
        log_warn "  players.db no encontrado"
    fi
    echo ""

    # Cuentas de usuario
    echo -e "  ${BLD}Cuentas registradas (db/${SERVER_NAME}.db):${RST}"
    if [[ -f "$USERS_DB" ]] && command -v sqlite3 &>/dev/null; then
        sqlite3 "$USERS_DB" "SELECT id,username,role,lastConnection FROM whitelist;" 2>/dev/null | \
            sed 's/^/    /' || echo -e "    ${DIM}(error al leer DB)${RST}"
    elif [[ -f "$USERS_DB" ]]; then
        echo -e "    $(du -sh "$USERS_DB" | cut -f1) (sqlite3 no instalado para listar)"
    fi
    echo ""

    # Vehículos
    echo -e "  ${BLD}Vehículos (vehicles.db):${RST}"
    if [[ -f "${SAVE_DIR}/vehicles.db" ]]; then
        echo -e "    $(du -sh "${SAVE_DIR}/vehicles.db" | cut -f1)"
    else
        log_warn "  vehicles.db no encontrado"
    fi
    echo ""

    # Backups existentes
    echo -e "  ${BLD}Backups existentes:${RST}"
    if [[ -d "$BACKUP_BASE" ]]; then
        local backup_list
        backup_list=$(ls -t "$BACKUP_BASE" 2>/dev/null | head -5)
        if [[ -n "$backup_list" ]]; then
            echo "$backup_list" | while read -r b; do
                local bsize; bsize=$(du -sh "${BACKUP_BASE}/${b}" 2>/dev/null | cut -f1)
                echo -e "    ${bsize}  ${b}"
            done
        else
            echo -e "    ${DIM}(ningún backup encontrado)${RST}"
        fi
    else
        echo -e "    ${DIM}(carpeta backups/ no existe aún)${RST}"
    fi

    press_enter
}

# ════════════════════════════════════════════════════════════════════════════
#  MODO 7: RESTAURAR SANDBOXVARS DESDE EL ÚLTIMO WIPE/BACKUP
# ════════════════════════════════════════════════════════════════════════════
mode_restaurar_sandbox() {
    echo ""
    big_sep
    echo -e "${BLD}  MODO 7 — RESTAURAR CONFIGURACIÓN SANDBOX DESDE EL ÚLTIMO WIPE${RST}"
    big_sep
    echo ""
    echo -e "  Esta opción recupera tu archivo SandboxVars.lua personalizado"
    echo -e "  desde el backup más reciente."
    echo ""

    # Verificar si el servidor está corriendo
    if pgrep -f "zombie.SSR|projectzomboid|ProjectZomboid" &>/dev/null; then
        echo ""
        log_error "CRÍTICO: El servidor de Project Zomboid parece estar EJECUTÁNDOSE."
        log_error "Si restauramos el archivo con el servidor prendido, cuando lo apagues"
        log_error "el servidor volverá a sobrescribir el archivo con su memoria RAM."
        echo ""
        log_warn "Por favor, apaga completamente el servidor antes de continuar."
        press_enter
        return 1
    fi

    # Buscar el último backup que contenga config/servertest_SandboxVars.lua
    if [[ ! -d "$BACKUP_BASE" ]]; then
        log_error "No existe la carpeta de backups todavía."
        press_enter
        return 1
    fi

    local last_backup=""
    # Buscar carpetas de backups ordenadas por fecha de creación (de más nueva a más vieja)
    while IFS= read -r dir; do
        if [[ -f "${dir}/config/${SERVER_NAME}_SandboxVars.lua" ]]; then
            last_backup="$dir"
            break
        fi
    done < <(find "$BACKUP_BASE" -maxdepth 2 -type d -name "${SERVER_NAME}_*" | sort -r)

    if [[ -z "$last_backup" ]]; then
        # Buscar en subcarpetas (por si está dentro de L4P u otras carpetas)
        while IFS= read -r dir; do
            if [[ -f "${dir}/config/${SERVER_NAME}_SandboxVars.lua" ]]; then
                last_backup="$dir"
                break
            fi
        done < <(find "$BACKUP_BASE" -type d -name "${SERVER_NAME}_*" | sort -r)
    fi

    if [[ -z "$last_backup" ]]; then
        log_error "No se encontró ningún backup que contenga una configuración de SandboxVars."
        press_enter
        return 1
    fi

    log_info "Último backup detectado: ${BLD}$(basename "$last_backup")${RST}"
    log_info "Ubicación: ${last_backup}"
    echo ""
    log_info "Variables personalizadas del backup:"
    # Mostrar un resumen rápido de las variables clave
    if command -v grep &>/dev/null; then
        grep -E "MinutesPerPage|ElecShutModifier" "${last_backup}/config/${SERVER_NAME}_SandboxVars.lua" | sed 's/^/    /' || true
    fi
    echo ""

    if ! confirm "¿Deseas restaurar esta configuración sandbox sobre el servidor activo?"; then
        echo "  Operación cancelada."; return 0
    fi

    # Copiar el archivo
    if $DRY_RUN; then
        echo -e "  ${YEL}[DRY]${RST} Copiaría ${last_backup}/config/${SERVER_NAME}_SandboxVars.lua a ${SERVER_CONFIG_DIR}/${SERVER_NAME}_SandboxVars.lua"
    else
        cp "${last_backup}/config/${SERVER_NAME}_SandboxVars.lua" "${SERVER_CONFIG_DIR}/${SERVER_NAME}_SandboxVars.lua"
        log_ok "Archivo SandboxVars.lua restaurado con éxito."
    fi

    press_enter
}

# ════════════════════════════════════════
#  RESUMEN POST-WIPE
# ════════════════════════════════════════
print_success_summary() {
    local tipo="${1:-wipe}"
    echo ""
    big_sep
    echo -e "${GRN}${BLD}  ✓ WIPE ${tipo^^} COMPLETADO${RST}"
    big_sep
    echo ""
    echo -e "  ${BLD}Backup guardado en:${RST}"
    echo -e "  ${CYN}${LAST_BACKUP_PATH:-${BACKUP_BASE}}${RST}"
    echo ""
    echo -e "  ${BLD}Archivos protegidos intactos:${RST}"
    log_never "db/${SERVER_NAME}.db (usuarios y whitelist)"
    log_never "players.db"
    log_never "vehicles.db"
    echo ""
    
    echo -e "  ${RED}${BLD}⚠️ ADVERTENCIA CRÍTICA DE PROJECT ZOMBOID B42:${RST}"
    echo -e "  Al detectar un nuevo mapa (porque borramos map_meta.bin),"
    echo -e "  el servidor de PZ automáticamente ${YEL}sobrescribe y resetea${RST}"
    echo -e "  el archivo ${BLD}Server/${SERVER_NAME}_SandboxVars.lua${RST} con los valores por defecto."
    echo ""
    echo -e "  ${GRN}¿Cómo restaurar tu configuración personalizada?${RST}"
    echo -e "  1. Arranca tu servidor una vez para que PZ genere el nuevo mapa."
    echo -e "  2. ${RED}Apaga por completo${RST} el servidor."
    echo -e "  3. Restaura tu archivo de configuración del backup ejecutando:"
    echo -e "     ${CYN}cp \"${LAST_BACKUP_PATH:-${BACKUP_BASE}}/config/${SERVER_NAME}_SandboxVars.lua\" \"${SERVER_CONFIG_DIR}/${SERVER_NAME}_SandboxVars.lua\"${RST}"
    echo -e "  4. Vuelve a iniciar el servidor. Ahora cargará tus opciones correctamente."
    echo ""
    echo -e "  ${DIM}Si necesitas revertir todo, copia la carpeta save del backup a Saves/Multiplayer/${SERVER_NAME}/${RST}"
    echo ""
}

LAST_BACKUP_PATH=""

# ════════════════════════════════════════════════════════════════════════════
#  MENÚ PRINCIPAL
# ════════════════════════════════════════════════════════════════════════════
main_menu() {
    while true; do
        [[ -t 1 ]] && clear || true
        echo ""
        big_sep
        echo -e "${BLD}   PZ WIPE TOOL — ${SERVER_NAME} (Build 42)${RST}"
        big_sep
        echo ""
        echo -e "  ${DIM}Save:    ${SAVE_DIR}${RST}"
        echo -e "  ${DIM}Config:  ${SERVER_CONFIG_DIR}${RST}"
        echo -e "  ${DIM}DB:      ${USERS_DB}${RST}"
        echo -e "  ${DIM}Backup:  ${BACKUP_BASE}${RST}"
        echo ""
        separator
        echo ""

        # Estado rápido del save
        local chunk_count="?"
        [[ -d "${SAVE_DIR}/map" ]] && chunk_count=$(find "${SAVE_DIR}/map" -name "*.bin" 2>/dev/null | wc -l)
        echo -e "  Chunks en el mapa actual: ${BLD}${chunk_count}${RST}"
        echo ""
        separator
        echo ""

        echo -e "  ${BLD}[1]${RST} Wipe ${RED}COMPLETO${RST}"
        echo -e "      → Resetea TODO el mapa. Preserva jugadores, vehículos y cuentas."
        echo ""
        echo -e "  ${BLD}[2]${RST} Wipe ${YEL}PARCIAL${RST}"
        echo -e "      → Igual que completo, pero preserva el historial de zonas exploradas."
        echo ""
        echo -e "  ${BLD}[3]${RST} Wipe ${MAG}SELECTIVO${RST} (con bases)"
        echo -e "      → Preserva chunks específicos donde hay construcciones."
        echo -e "      → Sub-opciones: por coordenadas / por timestamp / combinado."
        echo ""
        echo -e "  ${BLD}[4]${RST} Solo ${GRN}BACKUP${RST} (sin wipe)"
        echo -e "      → Respalda save + config + db sin tocar nada."
        echo ""
        echo -e "  ${BLD}[5]${RST} Ver ${CYN}ESTADO${RST} del save"
        echo -e "      → Info del mapa, jugadores, backups existentes."
        echo ""
        echo -e "  ${BLD}[6]${RST} Activar/Desactivar modo ${YEL}DRY-RUN${RST} (simular sin borrar)"
        if $DRY_RUN; then
            echo -e "      ${YEL}▶ DRY-RUN ACTIVO — nada será borrado realmente${RST}"
        else
            echo -e "      ${DIM}▶ DRY-RUN desactivado (modo real)${RST}"
        fi
        echo ""
        echo -e "  ${BLD}[7]${RST} Restaurar ${GRN}SandboxVars.lua${RST} desde el último Wipe"
        echo -e "      → Corrige el reseteo automático de PZ B42 de forma rápida."
        echo ""
        echo -e "  ${BLD}[0]${RST} Salir"
        echo ""
        separator
        echo ""
        echo -ne "  Elige opción: "
        read -r opcion

        case "$opcion" in
            1) mode_wipe_completo ;;
            2) mode_wipe_parcial ;;
            3) mode_wipe_selectivo ;;
            4) mode_solo_backup ;;
            5) mode_estado ;;
            6)
                if $DRY_RUN; then
                    DRY_RUN=false
                    log_ok "Modo DRY-RUN desactivado. Las operaciones serán REALES."
                else
                    DRY_RUN=true
                    log_warn "Modo DRY-RUN activado. Las operaciones solo se simularán."
                fi
                press_enter
                ;;
            7) mode_restaurar_sandbox ;;
            0)
                echo ""
                echo -e "  ${DIM}Saliendo de PZ Wipe Tool.${RST}"
                echo ""
                exit 0
                ;;
            *)
                log_warn "Opción inválida: '${opcion}'"
                press_enter
                ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════════════════════
#  PUNTO DE ENTRADA
# ════════════════════════════════════════════════════════════════════════════

# Modo no-interactivo (para automatización / CI)
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_warn "Ejecutando en modo dry-run (no interactivo)."
fi

validate_environment
main_menu
