#!/usr/bin/env bash
set -euo pipefail

# --------- CONFIG ----------
export COMFY_PORT="${COMFY_PORT:-8188}"
export WORKDIR="${WORKDIR:-/workspace}"
export COMFY_DIR="$WORKDIR/ComfyUI"
export MODELS_DIR="${MODELS_DIR:-$WORKDIR/models}"

# Optional dynamic node list sources:
# 1) NODES_URL: http(s) URL to a newline-separated list (e.g. secret Gist raw URL)
#    Each line: either "https://github.com/owner/repo.git" or "https://github.com/owner/repo.git@TAG_OR_COMMIT"
# 2) NODES_LIST: multi-line string with same content as above
# 3) comfyui_nodes.txt: repo-relative fallback file (same format)
export NODES_URL="${NODES_URL:-}"
export NODES_LIST="${NODES_LIST:-}"
# Optional: extra curl headers (one per line) for private endpoints, e.g.:
# NODES_HEADERS='Authorization: Bearer <TOKEN>'
export NODES_HEADERS="${NODES_HEADERS:-}"
# ---------------------------

echo "[*] Preparing environment..."
apt-get update -y && apt-get install -y git aria2 curl jq >/dev/null || true
pip install --upgrade pip >/dev/null
pip install -r requirements.txt >/dev/null || true

mkdir -p "$MODELS_DIR" "$COMFY_DIR/custom_nodes"

# 1) ComfyUI
if [ ! -d "$COMFY_DIR/.git" ]; then
  echo "[*] Cloning ComfyUI..."
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
fi

fetch_nodes_list() {
  # echo lines of repos to stdout
  if [ -n "$NODES_URL" ]; then
    echo "[*] Fetching nodes list from NODES_URL..."
    if [ -n "$NODES_HEADERS" ]; then
      # Split NODES_HEADERS by newline and build -H args
      hdr_args=()
      while IFS= read -r h; do
        [ -z "$h" ] && continue
        hdr_args+=(-H "$h")
      done <<< "$NODES_HEADERS"
      curl -fsSL "${hdr_args[@]}" "$NODES_URL"
    else
      curl -fsSL "$NODES_URL"
    fi
    return
  fi
  if [ -n "$NODES_LIST" ]; then
    echo "[*] Using inline NODES_LIST for nodes..."
    printf "%s\n" "$NODES_LIST"
    return
  fi
  if [ -f comfyui_nodes.txt ]; then
    echo "[*] Using comfyui_nodes.txt..."
    cat comfyui_nodes.txt
    return
  fi
  echo "[*] No node list provided."
}

install_nodes() {
  local list="$1"
  [ -z "$list" ] && return 0
  echo "$list" | while IFS= read -r repo; do
    repo="$(echo "$repo" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -z "$repo" ] && continue
    case "$repo" in \#*) continue;; esac

    # Allow @ref suffix to pin commit/tag/branch
    ref=""
    if echo "$repo" | grep -q '@'; then
      ref="${repo##*@}"
      repo="${repo%@*}"
    fi

    name="$(basename "$repo" .git)"
    dest="$COMFY_DIR/custom_nodes/$name"
    if [ ! -d "$dest/.git" ]; then
      echo "[*] Cloning $repo -> $dest"
      git clone --depth=1 "$repo" "$dest" || true
    fi
    if [ -n "$ref" ]; then
      echo "[*] Pinning $name to $ref"
      (cd "$dest" && git fetch --all --tags -q && git checkout -q "$ref" || git checkout -q FETCH_HEAD || true)
    fi

    # Install per-node requirements if present
    if [ -f "$dest/requirements.txt" ]; then
      echo "[*] Installing requirements for $name"
      pip install -r "$dest/requirements.txt" || true
    fi
  done
}

nodes_list="$(fetch_nodes_list || true)"
install_nodes "$nodes_list"

# Link models dir
ln -sfn "$MODELS_DIR" "$COMFY_DIR/models"

# Start ComfyUI headless
echo "[*] Starting ComfyUI headless on :$COMFY_PORT ..."
python "$COMFY_DIR/main.py" --listen 0.0.0.0 --port "$COMFY_PORT" --enable-cors &

# Wait for API
for i in {1..90}; do
  curl -sf "http://127.0.0.1:$COMFY_PORT/system_stats" >/dev/null && break || sleep 1
done

# Start the RunPod serverless handler
echo "[*] Starting serverless worker..."
python worker.py
