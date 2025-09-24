# Comfy Remote Serverless Extension

Adds a **Remote: ON/OFF** toggle to ComfyUI that hijacks the **Queue** button and runs the prompt on a **RunPod Serverless** worker.  
While the job runs, shows a **fake KSampler steps progress bar** (configurable).  
When finished, the worker returns base64 images which the extension posts to my local `/remote/save` endpoint so they appear in my ComfyUI.

---

## What this is (mental model)

- I keep using **my local ComfyUI UI**.
- When **Remote is ON**, clicking **Queue** sends the **same API JSON** the UI would post to `/prompt`, but to RunPod’s `/run` endpoint instead.
- The worker executes headless, returns images as base64; I save them locally via the **Remote Sink Node** (`/remote/save`) and view them in a **Directory Image Loader**.

---

## Prereqs

- Local ComfyUI running (`http://127.0.0.1:8188`)
- **Remote Sink Node** installed locally to accept results:
  - File: `ComfyUI/custom_nodes/remote_sink.py`
  - It exposes `POST /remote/save` and writes images to `./remote_results`
  - Add a **Directory Image Loader** pointed at `./remote_results` so results show up automatically
- A **RunPod Serverless** endpoint created from my serverless worker repo (`bash start.sh`)

---

## Install (local)

1. Copy `web/extensions/remote_serverless.js` →  
   `ComfyUI/web/extensions/remote_serverless.js`
2. Refresh the ComfyUI page.  
   I should see **“Remote: OFF”** and a **“Remote Config”** button in the top bar.

---

## Configure

Click **Remote Config** and set:

- **Endpoint**:  
  `https://api.runpod.ai/v2/<ENDPOINT_ID>/run`
- **API key**: my RunPod token
- **Fake ms/step**: how fast the fake progress bar fills (e.g., `300–1200` ms/step).  
  I can tune this later to roughly match my typical runtimes.

---

## Using a model whitelist (repo list)

If I want the worker to **ensure** needed models and **prune** the rest each run:

1. Add a **Text (multiline)** node in my graph titled exactly `repo_list`
2. Paste one link per line, optionally prefix with a
