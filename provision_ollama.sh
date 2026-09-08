#!/usr/bin/env bash
# provision_ollama.sh — pod de LLM (Ollama + Open WebUI) para RunPod.
#
# Se ejecuta en cada arranque desde el Container Start Command. Idempotente:
# cada fase se salta el trabajo ya hecho. No aborta al primer error — los
# problemas se acumulan en FAILED y se reportan en el resumen final.
#
# Uso:
#   bash provision_ollama.sh              # arranque normal, descarga modelos
#   SKIP_MODELS=true bash provision_ollama.sh   # solo servicios, sin descargar
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

# Modelos a descargar. Edita esta lista para probar otros.
MODELS=(
    "juilpark/gemma-4-31B-it-uncensored-heretic"
    "dolphin3.0-mistral-24b"
)

FAILED=()

log() { printf '%s\n' "$*" | tee -a "$LOG"; }
fail() { FAILED+=("$1"); log "[ERROR] $1"; }

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

# ───────────────────────────── Fase 1: Ollama ─────────────────────────────

install_ollama() {
    if command -v ollama >/dev/null 2>&1; then
        log "Ollama ya presente: $(ollama --version 2>/dev/null | head -1)"
        return 0
    fi

    log "Instalando Ollama (última versión)..."

    # Tarball oficial en vez del script de instalación: el script crea usuarios
    # y unidades de systemd que no existen en un contenedor, y falla de formas
    # difíciles de diagnosticar. El tarball es la vía documentada para
    # instalaciones manuales y solo desempaqueta el binario.
    #
    # Siempre la última versión, nunca la congelada en la imagen: un Ollama
    # antiguo no trae el renderer de Gemma 4 y el modelo responde guiones.
    local tgz="/tmp/ollama-linux-amd64.tgz"

    if ! curl -fL --retry 3 https://ollama.com/download/ollama-linux-amd64.tgz \
        -o "$tgz" >>"$LOG" 2>&1; then
        fail "No se pudo descargar el tarball de Ollama. Revisa $LOG."
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
    nohup ollama serve >>"$LOG" 2>&1 </dev/null &

    local i
    for i in $(seq 1 60); do
        if curl -sf "http://127.0.0.1:11434/api/version" >/dev/null 2>&1; then
            log "Ollama listo."
            return 0
        fi
        sleep 1
    done

    fail "Ollama no respondió en 60 segundos."
    return 1
}

# ──────────────────────────── Fase 2: modelos ────────────────────────────

pull_models() {
    if [[ "$SKIP_MODELS" == "true" ]]; then
        log "[SKIP] Descarga de modelos desactivada con SKIP_MODELS=true."
        return 0
    fi

    local model
    for model in "${MODELS[@]}"; do
        if ollama list 2>/dev/null | grep -Fq "$model"; then
            log "   ✓ ya presente: $model"
            continue
        fi

        log "   ↓ descargando: $model"

        if ! ollama pull "$model" >>"$LOG" 2>&1; then
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

    log "Instalando Open WebUI (tarda unos minutos)..."

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
    nohup open-webui serve --host 0.0.0.0 --port "$WEBUI_PORT" >>"$LOG" 2>&1 </dev/null &

    local i
    for i in $(seq 1 180); do
        if curl -sf "http://127.0.0.1:${WEBUI_PORT}/health" >/dev/null 2>&1; then
            log "Open WebUI listo."
            return 0
        fi
        sleep 1
    done

    fail "Open WebUI no respondió en 180 segundos. Revisa $LOG."
    return 1
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
    check_python || { summary; return 1; }

    install_ollama && start_ollama && pull_models
    install_webui && start_webui

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
