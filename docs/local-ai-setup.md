# Local AI Setup

Scribeosaur runs transcript prompts locally through a managed Python + `mlx-lm` runtime on Apple Silicon.

## Runtime behavior

- `ffmpeg`, `yt-dlp`, `deno`, and `uv` are provisioned on first launch if they are not already bundled in the app
- the local AI runtime is installed or repaired under `~/Library/Application Support/Scribeosaur/ai-runtime`
- the default local model downloads, verifies, and loads on first launch, then is stored under `~/Library/Application Support/Scribeosaur/models`
- if the installer bundle contains a pre-seeded model under `Contents/Resources/ModelSeed/<model-id>`, Scribeosaur installs that copy before attempting any network download
- if the installer bundle contains a pre-seeded runtime under `Contents/Resources/AIRuntimeSeed`, Scribeosaur installs that copy before attempting any network runtime bootstrap
- startup stays blocked until the runtime is healthy and the selected model is loaded into memory

## Installer behavior

The release packaging flow is implemented by [`scripts/build-release-installer.sh`](/Users/bdoug/Documents/Coding/flowscribe/scripts/build-release-installer.sh).

The script:

- archives the app
- injects bundled `ffmpeg`, `yt-dlp`, `deno`, and `uv` binaries into the app bundle
- optionally injects a pre-seeded offline model
- optionally injects a pre-seeded offline AI runtime
- signs the app with `DEVELOPER_ID_APP`
- builds a signed installer package with `DEVELOPER_ID_INSTALLER`
- optionally notarizes the package and final DMG when `NOTARY_PROFILE` is provided

## Example

```bash
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)" \
NOTARY_PROFILE="scribeosaur-notary" \
MODEL_SEED_PATH="/absolute/path/to/model/folder" \
AI_RUNTIME_SEED_PATH="/absolute/path/to/ai-runtime/folder" \
./scripts/build-release-installer.sh
```
