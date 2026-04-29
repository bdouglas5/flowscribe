#!/usr/bin/env python3

import gc
import json
import sys
import traceback

from mlx_lm import load, stream_generate


model = None
tokenizer = None
loaded_model_path = None


def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def emit_error(request_id, error):
    emit(
        {
            "id": request_id,
            "event": "error",
            "message": str(error),
            "traceback": traceback.format_exc(),
        }
    )


def build_prompt(messages):
    kwargs = {
        "add_generation_prompt": True,
        "enable_thinking": False,
    }

    try:
        return tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            **kwargs,
        )
    except TypeError:
        try:
            return tokenizer.apply_chat_template(
                messages,
                **kwargs,
            )
        except TypeError:
            fallback_kwargs = {
                "add_generation_prompt": True,
            }

            try:
                return tokenizer.apply_chat_template(
                    messages,
                    tokenize=False,
                    **fallback_kwargs,
                )
            except TypeError:
                return tokenizer.apply_chat_template(
                    messages,
                    **fallback_kwargs,
                )


def handle_load(request):
    global model, tokenizer, loaded_model_path

    requested_path = request["modelPath"]
    if loaded_model_path == requested_path and model is not None and tokenizer is not None:
        emit({"id": request["id"], "event": "loaded"})
        return

    model, tokenizer = load(requested_path, lazy=True)
    loaded_model_path = requested_path
    emit({"id": request["id"], "event": "loaded"})


def handle_unload(request):
    global model, tokenizer, loaded_model_path

    model = None
    tokenizer = None
    loaded_model_path = None
    gc.collect()
    emit({"id": request["id"], "event": "unloaded"})


def handle_generate(request):
    if model is None or tokenizer is None:
        raise RuntimeError("The model is not loaded.")

    prompt = build_prompt(request["messages"])
    accumulated = []

    for response in stream_generate(
        model,
        tokenizer,
        prompt,
        max_tokens=request.get("maxTokens", 256),
    ):
        text = response.text
        if text:
            accumulated.append(text)
            emit({"id": request["id"], "event": "token", "text": text})

    emit({"id": request["id"], "event": "done", "text": "".join(accumulated)})


def handle_health(request):
    emit(
        {
            "id": request["id"],
            "event": "healthy",
            "loadedModelPath": loaded_model_path,
        }
    )


def main():
    emit({"event": "ready", "protocolVersion": 1})

    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
            command = request["command"]

            if command == "loadModel":
                handle_load(request)
            elif command == "unloadModel":
                handle_unload(request)
            elif command == "generate":
                handle_generate(request)
            elif command == "health":
                handle_health(request)
            else:
                raise RuntimeError(f"Unsupported command: {command}")
        except Exception as error:  # noqa: BLE001
            request_id = None
            try:
                request_id = request.get("id")
            except Exception:  # noqa: BLE001
                pass
            emit_error(request_id, error)


if __name__ == "__main__":
    main()
