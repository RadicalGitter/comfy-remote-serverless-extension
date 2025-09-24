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
2. Paste one link per line, optionally prefix with a type:

ckpt https://civitai.com/api/download/models/1612720
ckpt https://civitai.com/api/download/models/2095926
lora https://civitai.com/api/download/models/383563
lora https://civitai.com/api/download/models/1285854
vae https://civitai.com/api/download/models/160240

The extension will send this text as `repo_list` in the serverless payload; the worker will:
- Download any missing models into canonical filenames
- Delete other `.safetensors` so the pod stays lean
- Then run my prompt

> Tip: If I don’t want ensure/prune on a given run, just clear the `repo_list` node or toggle Remote OFF.

---

## Run flow (what happens when I click Queue)

1. If **Remote: ON**, the extension:
   - Builds the **API prompt JSON** from the current graph
   - Reads `repo_list` (if present)
   - `POST /run` on RunPod with `{input: { action:"run", repo_list, prompt }}`
2. Shows a **fake KSampler progress** bar using the total steps it finds in my KSampler nodes
3. Polls `/status/<id>` until **COMPLETED**
4. Sends `{images:[{b64:"..."}]}` to my local **`/remote/save`** (Remote Sink Node)
5. My local **Directory Image Loader** picks up the new files from `./remote_results`

---

## Notes & gotchas

- **No live per-node highlighting** (Serverless has no `/ws` stream). The progress bar is **estimated** (by steps × ms/step).
- The extension **doesn’t** alter my graph. It just diverts the queue call when Remote is ON.
- **CORS**: ComfyUI is started with `--enable-cors` in the worker’s `start.sh`.
- If I see “completed but returned no images”, check that I have at least one **Save Image** node in my graph.
- Large payloads are fine; the prompt JSON is POSTed as a single body.
- If the worker says it can’t find a model path, use `repo_list` so it downloads the exact versions I want.

---

## Troubleshooting

**Remote button does nothing**
- Ensure the file is exactly at `ComfyUI/web/extensions/remote_serverless.js`
- Open browser devtools → Console → check for JS errors

**Images don’t appear locally**
- Confirm the Remote Sink Node is installed: `custom_nodes/remote_sink.py`
- Try: `curl -X POST http://127.0.0.1:8188/remote/save -H "Content-Type: application/json" -d "{\"images\": []}"`
  - Should return `{"saved":[]}` (i.e., endpoint exists)
- Make sure my **Directory Image Loader** points to `./remote_results`

**Worker runs but fails downloads**
- Try using **Civitai API** links instead of page links, e.g.  
  `https://civitai.com/api/download/models/1612720`
- Keep repo list small for the first test (one ckpt)

**Progress bar feels wrong**
- Open **Remote Config** and adjust **Fake ms/step** until it “looks right”

---

## Security tips (for me)

- Never commit keys or tokens (add them to `.gitignore` first)
- If I accidentally expose a key:
  - Revoke it in GitHub **immediately**
  - Remove it from repo history (e.g., `git filter-repo`)
  - Generate a fresh key and update remotes

---

## Uninstall

- Delete `ComfyUI/web/extensions/remote_serverless.js`
- Restart/refresh ComfyUI

---

## Roadmap (nice-to-have for later)

- Optional: “progress events” proxy when using a Managed Pod (via WebSocket)
- Config UI with a proper modal instead of prompt()
- Per-run override to skip `repo_list`
- Return extra artifacts (e.g., metadata txt) alongside images

---

## License

MIT © 2025 Oscar Bergqvist
