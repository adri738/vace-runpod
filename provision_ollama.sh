#!/usr/bin/env bash
# provision_ollama.sh — pod de LLM (Ollama + Open WebUI) para RunPod.
#
# Se ejecuta en cada arranque desde el Container Start Command. Idempotente:
# cada fase se salta el trabajo ya hecho. No aborta al primer error — los
# problemas se acumulan en FAILED y se reportan en el resumen final.
#
# Uso:
#   bash provision_ollama.sh                     # arranque normal
#   SKIP_MODELS=true bash provision_ollama.sh    # solo servicios, sin modelos
#   KEEP_ALIVE=false bash provision_ollama.sh    # a mano, devuelve el prompt
#
# Diseño: todo efecto secundario vive dentro de una función, para que el
# archivo se pueda leer sin ejecutar nada.

set -uo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
LOG="${OLLAMA_PROVISION_LOG:-$WORKSPACE/provision_ollama.log}"
SKIP_MODELS="${SKIP_MODELS:-false}"

# Los pesos y la configuración viven en el volumen, no en el disco del
# contenedor, que es pequeño.
export OLLAMA_MODELS="${OLLAMA_MODELS:-$WORKSPACE/ollama}"
export OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}"
export OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-0}"
export OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-1}"
export DATA_DIR="${DATA_DIR:-$WORKSPACE/open-webui}"

WEBUI_PORT="${WEBUI_PORT:-8080}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"

# Modelos a descargar. Edita esta lista para probar otros.
MODELS=(
    "juilpark/gemma-4-31B-it-uncensored-heretic"
    "dolphin3.0-mistral-24b"
)

FAILED=()

log() { printf '%s\n' "$*" | tee -a "$LOG"; }
fail() { FAILED+=("$1"); log "[ERROR] $1"; }

# Opciones comunes de curl para descargas grandes.
#
#   --ipv4        algunos contenedores de RunPod anuncian IPv6 y no lo enrutan;
#                 curl lo prefiere, se conecta, y la transferencia nunca avanza.
#   --speed-limit / --speed-time
#                 aborta si baja de 2 KB/s durante 30 segundos. Sin esto una
#                 descarga estancada se queda colgada indefinidamente:
#                 --connect-timeout solo cubre el establecimiento de conexión.
#   -C -          reanuda si ya hay un archivo parcial de un intento anterior.
CURL_BIG=(
    --fail --location --ipv4
    --connect-timeout 10
    --speed-limit 2048 --speed-time 30
    --max-time 1800
    --retry 2 --retry-delay 3
    -C -
)

# ───────────────────────── Comprobaciones previas ─────────────────────────

check_python() {
    local version
    version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)" || {
        fail "No hay python3 en la imagen."
        return 1
    }

    log "Python: $version"

    # Open WebUI exige 3.11 o superior.
    if [[ "$(printf '%s\n3.11\n' "$version" | sort -V | head -1)" != "3.11" ]]; then
        fail "Python $version es demasiado antiguo para Open WebUI (necesita 3.11+). Despliega con una imagen runpod/pytorch que traiga py3.11."
        return 1
    fi
}

check_gpu() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        log "GPU: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | head -1)"
    else
        fail "nvidia-smi no disponible: el pod no ve la GPU."
    fi
}

# ─────────────────────────── Diagnóstico de red ───────────────────────────

# La salida de red de un pod de RunPod puede estar rota solo para ciertos
# destinos: PyPI responde y el resto no. Eso nos costó veinte minutos de espera
# ciega, así que ahora se comprueba en los primeros segundos y queda escrito en
# el log con nombre y apellido.
network_preflight() {
    log ""
    log "── Salida de red ──"

    local host
    for host in ollama.com github.com objects.githubusercontent.com pypi.org; do
        if getent hosts "$host" >/dev/null 2>&1; then
            log "   DNS  ok    $host"
        else
            log "   DNS  FALLA $host"
        fi
    done
}

# Descarga los primeros 256 KB de una URL y devuelve 0 si llegaron rápido.
# Sirve para elegir origen antes de comprometerse a bajar 1.5 GB por un camino
# que no avanza.
#
# No mira el código de salida de curl: un servidor que ignora el Range devuelve
# el archivo entero y curl termina en timeout, pero los bytes llegaron. Lo que
# importa es cuántos bytes se movieron.
probe_origin() {
    local url="$1" got
    got="$(curl --silent --location --ipv4 \
        --connect-timeout 10 --max-time 25 \
        --range 0-262143 -o /dev/null \
        --write-out '%{size_download}' "$url" 2>/dev/null)"

    # Algunas versiones de curl imprimen el tamaño con decimales; nos quedamos
    # con la parte entera para poder compararlo.
    got="${got%%[!0-9]*}"

    [[ "${got:-0}" -ge 65536 ]]
}

# Intenta una descarga con curl, y si falla con las otras herramientas que
# haya en la imagen. aria2c abre varias conexiones en paralelo y a veces pasa
# donde un flujo único se estanca.
try_fetch() {
    local url="$1" dest="$2"

    if curl "${CURL_BIG[@]}" "$url" -o "$dest" >>"$LOG" 2>&1; then
        return 0
    fi
    log "      curl no pudo."

    if command -v aria2c >/dev/null 2>&1; then
        log "      probando con aria2c (multiconexión)..."
        if aria2c -x 8 -s 8 -c --console-log-level=warn \
            --connect-timeout=10 --lowest-speed-limit=2K \
            -d "$(dirname "$dest")" -o "$(basename "$dest")" \
            "$url" >>"$LOG" 2>&1; then
            return 0
        fi
        log "      aria2c tampoco."
    fi

    if command -v wget >/dev/null 2>&1; then
        log "      probando con wget..."
        if wget -c -T 20 --read-timeout=30 --tries=2 \
            -O "$dest" "$url" >>"$LOG" 2>&1; then
            return 0
        fi
        log "      wget tampoco."
    fi

    return 1
}

# ───────────────────────────── Fase 1: Ollama ─────────────────────────────

# El tarball tiene alrededor de 1.5 GB. Un archivo mucho más pequeño casi
# siempre es una página de error guardada con nombre de tarball.
verify_tarball() {
    local tgz="$1" size
    size="$(stat -c %s "$tgz" 2>/dev/null || echo 0)"

    if (( size < 100000000 )); then
        log "      archivo incompleto ($((size / 1000000)) MB), se descarta."
        rm -f "$tgz"
        return 1
    fi

    if ! tar -tzf "$tgz" >/dev/null 2>&1; then
        log "      el archivo no es un tar.gz válido, se descarta."
        rm -f "$tgz"
        return 1
    fi
}

# Los assets de GitHub se sirven desde un dominio distinto al de la página.
# Resolver la etiqueta por la API nos da una tercera URL que puede salir por
# otro camino, y de paso confirma si GitHub es alcanzable.
ollama_origins() {
    echo "https://ollama.com/download/ollama-linux-amd64.tgz"
    echo "https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tgz"

    local tag
    tag="$(curl -fsL --ipv4 --max-time 20 \
        https://api.github.com/repos/ollama/ollama/releases/latest 2>/dev/null \
        | grep -m1 '"tag_name"' \
        | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"

    if [[ -n "${tag:-}" ]]; then
        echo "https://github.com/ollama/ollama/releases/download/${tag}/ollama-linux-amd64.tgz"
    fi
}

install_ollama() {
    if command -v ollama >/dev/null 2>&1; then
        log "Ollama ya presente: $(ollama --version 2>/dev/null | head -1)"
        return 0
    fi

    log ""
    log "── Instalando Ollama ──"

    # Tarball oficial en vez del script de instalación: el script crea usuarios
    # y unidades de systemd que no existen en un contenedor, y falla de formas
    # difíciles de diagnosticar. El tarball solo desempaqueta el binario.
    #
    # Siempre la última versión, nunca la congelada en la imagen: un Ollama
    # antiguo no trae el renderer de Gemma 4 y el modelo responde guiones.
    local tgz="/tmp/ollama-linux-amd64.tgz"
    local url round downloaded=false

    local origins=()
    mapfile -t origins < <(ollama_origins)
    log "   ${#origins[@]} origen(es) disponibles."

    # Dos rondas: un origen puede estar de mal humor un minuto y responder al
    # siguiente. Más de dos es hacer esperar al usuario por nada.
    for round in 1 2; do
        for url in "${origins[@]}"; do
            log "   [ronda $round] ${url#https://}"

            if ! probe_origin "$url"; then
                log "      sin respuesta útil en 25 s, siguiente origen."
                continue
            fi

            log "      responde. Descargando..."

            if try_fetch "$url" "$tgz" && verify_tarball "$tgz"; then
                downloaded=true
                break 2
            fi
        done

        (( round == 1 )) && log "   Ningún origen sirvió. Reintentando una vez más..."
    done

    if [[ "$downloaded" != "true" ]]; then
        fail "OLLAMA_SIN_RED: ningún origen entregó el tarball. La salida de red de este pod no alcanza los servidores de Ollama ni GitHub."
        return 1
    fi

    if ! tar -C /usr -xzf "$tgz" >>"$LOG" 2>&1; then
        fail "No se pudo desempaquetar el tarball de Ollama. Revisa $LOG."
        return 1
    fi

    rm -f "$tgz"

    if ! command -v ollama >/dev/null 2>&1; then
        fail "Ollama se desempaquetó pero el binario no está en el PATH."
        return 1
    fi

    log "Ollama instalado: $(ollama --version 2>/dev/null | head -1)"
}

start_ollama() {
    if curl -sf "http://127.0.0.1:11434/api/version" >/dev/null 2>&1; then
        log "Ollama ya está sirviendo."
        return 0
    fi

    mkdir -p "$OLLAMA_MODELS"

    log "Arrancando Ollama en $OLLAMA_HOST (modelos en $OLLAMA_MODELS)..."
    nohup ollama serve >>"$WORKSPACE/ollama.log" 2>&1 </dev/null &

    local i
    for i in $(seq 1 60); do
        if curl -sf "http://127.0.0.1:11434/api/version" >/dev/null 2>&1; then
            log "Ollama listo."
            return 0
        fi
        sleep 1
    done

    fail "Ollama no respondió en 60 segundos. Revisa $WORKSPACE/ollama.log."
    return 1
}

# ──────────────────────────── Fase 2: modelos ────────────────────────────

pull_models() {
    if [[ "$SKIP_MODELS" == "true" ]]; then
        log "[SKIP] Descarga de modelos desactivada con SKIP_MODELS=true."
        return 0
    fi

    log ""
    log "── Modelos ──"

    local model
    for model in "${MODELS[@]}"; do
        if ollama list 2>/dev/null | grep -Fq "$model"; then
            log "   ✓ ya presente: $model"
            continue
        fi

        log "   ↓ descargando: $model"

        if ! ollama pull "$model" >>"$WORKSPACE/ollama.log" 2>&1; then
            # No es fatal: el tag puede no existir en el registro. El resto
            # del pod sigue siendo utilizable.
            fail "No se pudo descargar '$model'. Comprueba el nombre en ollama.com; los tags no coinciden con HuggingFace."
            continue
        fi

        log "   ✓ descargado: $model"
    done
}

# ─────────────────────────── Fase 3: Open WebUI ───────────────────────────

install_webui() {
    if python3 -c 'import open_webui' >/dev/null 2>&1; then
        log "Open WebUI ya instalado."
        return 0
    fi

    log ""
    log "── Instalando Open WebUI (tarda unos minutos) ──"

    if ! python3 -m pip install --no-input --upgrade open-webui >>"$LOG" 2>&1; then
        fail "Falló la instalación de Open WebUI."
        return 1
    fi

    log "Open WebUI instalado."
}

start_webui() {
    if curl -sf "http://127.0.0.1:${WEBUI_PORT}/health" >/dev/null 2>&1; then
        log "Open WebUI ya está sirviendo."
        return 0
    fi

    mkdir -p "$DATA_DIR"

    log "Arrancando Open WebUI en el puerto ${WEBUI_PORT} (datos en $DATA_DIR)..."
    nohup open-webui serve --host 0.0.0.0 --port "$WEBUI_PORT" >>"$WORKSPACE/open-webui.log" 2>&1 </dev/null &

    local i
    for i in $(seq 1 180); do
        if curl -sf "http://127.0.0.1:${WEBUI_PORT}/health" >/dev/null 2>&1; then
            log "Open WebUI listo."
            return 0
        fi
        sleep 1
    done

    fail "Open WebUI no respondió en 180 segundos. Revisa $WORKSPACE/open-webui.log."
    return 1
}

# ────────────────────────────── Fase 4: Jupyter ──────────────────────────

# El Container Start Command sustituye al arranque propio de la imagen, que es
# quien lanza JupyterLab. Si no lo levantamos aquí, el puerto 8888 queda
# expuesto pero sin nada detrás.
start_jupyter() {
    if curl -sf "http://127.0.0.1:${JUPYTER_PORT}/api" >/dev/null 2>&1; then
        log "JupyterLab ya está sirviendo."
        return 0
    fi

    if ! command -v jupyter >/dev/null 2>&1; then
        log "[SKIP] JupyterLab no está en la imagen; usa el terminal web de RunPod."
        return 0
    fi

    log "Arrancando JupyterLab en el puerto ${JUPYTER_PORT}..."

    nohup jupyter lab \
        --ip=0.0.0.0 --port="$JUPYTER_PORT" --allow-root --no-browser \
        --ServerApp.token='' --ServerApp.password='' \
        --ServerApp.allow_origin='*' --notebook-dir=/workspace \
        >>"$WORKSPACE/jupyter.log" 2>&1 </dev/null &

    local i
    for i in $(seq 1 60); do
        if curl -sf "http://127.0.0.1:${JUPYTER_PORT}/api" >/dev/null 2>&1; then
            log "JupyterLab listo."
            return 0
        fi
        sleep 1
    done

    fail "JupyterLab no respondió en 60 segundos. Revisa $WORKSPACE/jupyter.log."
}

# ──────────────────────────────── Resumen ────────────────────────────────

summary() {
    log ""
    log "================================================"

    if (( ${#FAILED[@]} == 0 )); then
        log " ✅ POD LISTO"
        log ""
        log " Open WebUI  → puerto ${WEBUI_PORT}"
        log " Ollama API  → puerto 11434"
        log ""
        log " Modelos instalados:"
        ollama list 2>/dev/null | tee -a "$LOG"
    else
        log " ⚠️  POD ARRANCADO CON ${#FAILED[@]} PROBLEMA(S)"
        log ""
        local item
        for item in "${FAILED[@]}"; do
            log "  • $item"
        done

        # El fallo de red no se arregla con nada dentro del pod, así que la
        # única respuesta útil es decir exactamente qué hacer.
        if [[ " ${FAILED[*]} " == *OLLAMA_SIN_RED* ]]; then
            log ""
            log " ─────────────────────────────────────────────"
            log " Esto NO se arregla desde dentro del pod."
            log " Ningún origen entregó el binario, aunque PyPI"
            log " sí responda: es la salida de red de esta"
            log " máquina concreta."
            log ""
            log " Qué hacer:"
            log "   1. Termina este pod (Terminate, no Stop)."
            log "   2. Despliega otro en un datacenter distinto."
            log "   3. En el minuto uno, comprueba con:"
            log "      tail -f $LOG"
            log "      Si vuelve a salir OLLAMA_SIN_RED, cambia"
            log "      otra vez de región sin esperar más."
            log " ─────────────────────────────────────────────"
        fi

        log ""
        log " Log completo: $LOG"
    fi

    log "================================================"
}

main() {
    mkdir -p "$WORKSPACE"
    log ""
    log "======== provision_ollama.sh — $(date -u '+%Y-%m-%d %H:%M:%S UTC') ========"

    check_gpu
    network_preflight

    install_ollama && start_ollama && pull_models

    # Ollama no necesita Python, así que la comprobación va aquí y solo decide
    # sobre Open WebUI. Un pod con Ollama y sin interfaz sigue siendo usable
    # desde la terminal; abortar entero no ayudaba a nadie.
    if check_python; then
        install_webui && start_webui
    else
        log "[SKIP] Open WebUI omitido: la imagen no trae Python 3.11+."
    fi

    start_jupyter

    summary
    keep_alive
}

# El Container Start Command de RunPod es el proceso principal del contenedor:
# si termina, RunPod reinicia el pod. Los servicios corren en segundo plano con
# nohup, así que hay que bloquear aquí para que el contenedor siga vivo.
#
# Al ejecutarlo a mano desde una terminal, pasa KEEP_ALIVE=false para que
# devuelva el prompt.
keep_alive() {
    if [[ "${KEEP_ALIVE:-true}" != "true" ]]; then
        return 0
    fi

    log ""
    log "Contenedor activo. El log de aquí en adelante es el de los servicios."
    tail -f "$LOG"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
