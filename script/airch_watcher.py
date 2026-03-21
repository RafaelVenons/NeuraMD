#!/usr/bin/env python3
import json
import os
import shutil
import socket
import sys
import time
import traceback
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib import error, request


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def env_int(name: str, default: int) -> int:
    value = os.getenv(name, str(default)).strip()
    try:
        return int(value)
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    value = os.getenv(name, str(default)).strip()
    try:
        return float(value)
    except ValueError:
        return default


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
    os.replace(temp_path, path)


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def shorten(text: str, limit: int) -> str:
    normalized = " ".join(text.split())
    if len(normalized) <= limit:
        return normalized
    return normalized[: max(0, limit - 1)].rstrip() + "…"


def classify_job_status(payload: dict[str, Any]) -> str:
    value = str(payload.get("status") or "").strip().lower()
    if value in {"queued", "pending"}:
        return "pending"
    if value in {"running", "processing", "started", "working"}:
        return "running"
    if value in {"succeeded", "success", "done", "completed", "ok"}:
        return "succeeded"
    if value in {"failed", "error"}:
        return "failed"
    if payload.get("error"):
        return "failed"
    if payload.get("result"):
        return "succeeded"
    return "unknown"


@dataclass
class WatcherState:
    started_at: str = field(default_factory=utc_now)
    processed_total: int = 0
    succeeded_total: int = 0
    failed_total: int = 0
    last_job_id: str | None = None
    last_completed_at: str | None = None
    last_error: str | None = None
    active_job: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "started_at": self.started_at,
            "processed_total": self.processed_total,
            "succeeded_total": self.succeeded_total,
            "failed_total": self.failed_total,
            "last_job_id": self.last_job_id,
            "last_completed_at": self.last_completed_at,
            "last_error": self.last_error,
            "active_job": self.active_job,
        }

    @classmethod
    def from_path(cls, path: Path) -> "WatcherState":
        if not path.exists():
            return cls()
        try:
            payload = read_json(path)
        except Exception:
            return cls()

        state = cls()
        for key, value in payload.items():
            if hasattr(state, key):
                setattr(state, key, value)
        return state


class AirchWatcher:
    def __init__(self) -> None:
        self.shared_root = Path(os.getenv("SHARED_AI_ROOT", "/mnt/neuramd-share"))
        self.exchange_root = self.shared_root / "exchange"
        self.inbound_root = Path(os.getenv("AI_WATCHER_INBOUND", self.exchange_root / "inbound"))
        self.outbound_root = Path(os.getenv("AI_WATCHER_OUTBOUND", self.exchange_root / "outbound"))
        self.archive_root = Path(os.getenv("AI_WATCHER_ARCHIVE", self.exchange_root / "archive"))
        self.status_root = Path(os.getenv("AI_WATCHER_STATUS_ROOT", self.exchange_root / "status"))
        self.status_file = self.status_root / "status.json"
        self.waybar_file = self.status_root / "waybar.json"
        self.state_file = self.status_root / "state.json"
        self.poll_interval = env_float("AI_WATCHER_POLL_INTERVAL", 2.0)
        self.health_timeout = env_float("AI_WATCHER_HEALTH_TIMEOUT", 2.0)
        self.request_timeout = env_int("AI_WATCHER_REQUEST_TIMEOUT", 180)
        self.tooltip_job_limit = env_int("AI_WATCHER_TOOLTIP_JOBS", 5)
        self.base_url = os.getenv("OLLAMA_API_BASE", "http://127.0.0.1:11434").rstrip("/")
        self.default_model = os.getenv("OLLAMA_MODEL", "qwen2.5:1.5b")
        self.hostname = socket.gethostname()
        self.state = WatcherState.from_path(self.state_file)

        for directory in (
            self.inbound_root,
            self.outbound_root,
            self.archive_root / "processed",
            self.archive_root / "failed",
            self.archive_root / "invalid",
            self.status_root,
        ):
            directory.mkdir(parents=True, exist_ok=True)

    def run(self) -> None:
        while True:
            try:
                self.process_one_job()
                self.refresh_status()
            except KeyboardInterrupt:
                raise
            except Exception as exc:
                self.state.last_error = f"watcher crash loop: {exc}"
                self.write_status(
                    health={"ok": False, "message": str(exc)},
                    jobs=self.inspect_jobs(),
                    crash=traceback.format_exc(limit=5),
                )
            time.sleep(self.poll_interval)

    def write_state(self) -> None:
        atomic_write_json(self.state_file, self.state.as_dict())

    def inspect_jobs(self) -> dict[str, Any]:
        inbound_files = sorted(
            [path for path in self.inbound_root.glob("*.json") if path.is_file()],
            key=lambda item: item.stat().st_mtime,
        )
        outbound_files = sorted(
            [path for path in self.outbound_root.glob("*.json") if path.is_file()],
            key=lambda item: item.stat().st_mtime,
            reverse=True,
        )

        recent = []
        counts = {
            "pending": len(inbound_files),
            "running": 1 if self.state.active_job else 0,
            "succeeded": 0,
            "failed": 0,
            "unknown": 0,
        }

        for path in outbound_files[: self.tooltip_job_limit]:
            try:
                payload = read_json(path)
            except Exception:
                counts["unknown"] += 1
                recent.append({"file": path.name, "status": "unknown"})
                continue

            status = classify_job_status(payload)
            counts[status] = counts.get(status, 0) + 1
            recent.append(
                {
                    "file": path.name,
                    "id": payload.get("id"),
                    "status": status,
                    "completed_at": payload.get("completed_at"),
                    "error": shorten(str(payload.get("error") or ""), 120) if payload.get("error") else None,
                }
            )

        return {
            "counts": counts,
            "recent": recent,
            "active_job": self.state.active_job,
        }

    def check_ollama(self) -> dict[str, Any]:
        url = f"{self.base_url}/api/tags"
        req = request.Request(url, headers={"Accept": "application/json"})
        try:
            with request.urlopen(req, timeout=self.health_timeout) as response:
                payload = json.loads(response.read().decode("utf-8") or "{}")
        except error.URLError as exc:
            return {"ok": False, "message": str(exc.reason), "base_url": self.base_url}
        except Exception as exc:
            return {"ok": False, "message": str(exc), "base_url": self.base_url}

        models = [item.get("name") for item in payload.get("models", []) if item.get("name")]
        has_default_model = self.default_model in models if models else False
        return {
            "ok": True,
            "message": "reachable",
            "base_url": self.base_url,
            "model": self.default_model,
            "model_available": has_default_model,
            "models": models[:10],
        }

    def build_waybar_payload(self, health: dict[str, Any], jobs: dict[str, Any]) -> dict[str, Any]:
        counts = jobs["counts"]
        pending = counts["pending"]
        running = counts["running"]
        failed_total = self.state.failed_total

        if not health.get("ok"):
            css_class = "offline"
            alt = "offline"
            text = "󰖪 AI"
        elif self.state.last_error and failed_total > 0 and not self.state.active_job:
            css_class = "error"
            alt = "error"
            text = f"󰅙 AI {pending}"
        elif running or pending:
            css_class = "busy"
            alt = "busy"
            text = f"󱙺 AI {pending}"
            if running:
                text = f"󱙺 AI {running}+{pending}"
        else:
            css_class = "idle"
            alt = "idle"
            text = "󰚩 AI"

        tooltip_lines = [
            f"AIrch watcher @ {self.hostname}",
            f"Ollama: {'online' if health.get('ok') else 'offline'}",
            f"Modelo: {self.default_model}",
            f"Fila: {pending} pendente(s), {running} em execucao",
            f"Totais: {self.state.succeeded_total} ok / {self.state.failed_total} falha(s)",
        ]
        if self.state.active_job:
            tooltip_lines.append(f"Ativo: {self.state.active_job}")
        if self.state.last_error:
            tooltip_lines.append(f"Ultimo erro: {shorten(self.state.last_error, 180)}")
        for item in jobs["recent"]:
            label = item.get("id") or item["file"]
            suffix = f" erro={item['error']}" if item.get("error") else ""
            tooltip_lines.append(f"{item['status']}: {label}{suffix}")

        percentage = min(100, pending * 10 + running * 20)
        return {
            "text": text,
            "alt": alt,
            "class": css_class,
            "percentage": percentage,
            "tooltip": "\n".join(tooltip_lines),
        }

    def write_status(self, health: dict[str, Any], jobs: dict[str, Any], crash: str | None = None) -> dict[str, Any]:
        payload = {
            "updated_at": utc_now(),
            "host": self.hostname,
            "health": health,
            "jobs": jobs,
            "watcher": self.state.as_dict(),
        }
        if crash:
            payload["crash"] = crash
        waybar = self.build_waybar_payload(health, jobs)
        atomic_write_json(self.status_file, payload)
        atomic_write_json(self.waybar_file, waybar)
        self.write_state()
        return waybar

    def refresh_status(self) -> dict[str, Any]:
        health = self.check_ollama()
        jobs = self.inspect_jobs()
        return self.write_status(health=health, jobs=jobs)

    def next_job_file(self) -> Path | None:
        candidates = sorted(
            [path for path in self.inbound_root.glob("*.json") if path.is_file()],
            key=lambda item: item.stat().st_mtime,
        )
        return candidates[0] if candidates else None

    def claim_job(self, path: Path) -> Path:
        claimed = path.with_suffix(".processing.json")
        os.replace(path, claimed)
        return claimed

    def archive_job(self, claimed_path: Path, bucket: str) -> None:
        target_dir = self.archive_root / bucket
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / claimed_path.name.replace(".processing", "")
        if target.exists():
            target = target_dir / f"{claimed_path.stem}-{int(time.time())}.json"
        shutil.move(str(claimed_path), str(target))

    def outbound_path_for(self, request_id: str) -> Path:
        safe_id = "".join(char if char.isalnum() or char in {"-", "_"} else "_" for char in request_id)
        return self.outbound_root / f"{safe_id}.json"

    def build_prompt(self, capability: str, language: str | None) -> str:
        prompts = {
            "grammar_review": (
                "You are a grammar and spelling corrector.\n"
                "Fix only grammar, spelling, punctuation, and obvious typos.\n"
                "Preserve the original meaning, tone, structure, and Markdown formatting.\n"
                "Do not explain your changes.\n"
                "Return only the corrected text."
            ),
            "suggest": (
                "You are an editorial assistant.\n"
                "Improve clarity, flow, and readability while preserving meaning and Markdown formatting.\n"
                "Keep the text concise and natural.\n"
                "Do not explain your changes.\n"
                "Return only the revised text."
            ),
            "rewrite": (
                "You are a rewriting assistant.\n"
                "Rewrite the text to be clearer and more polished while preserving intent and Markdown formatting.\n"
                "Do not add explanations.\n"
                "Return only the rewritten text."
            ),
        }
        prompt = prompts.get(capability)
        if not prompt:
            raise ValueError(f"capability invalida: {capability}")
        if language:
            prompt += f"\n\nPreferred language of the output: {language}."
        return prompt

    def call_ollama(self, *, capability: str, text: str, language: str | None, model: str | None) -> dict[str, Any]:
        payload = {
            "model": model or self.default_model,
            "stream": False,
            "messages": [
                {"role": "system", "content": self.build_prompt(capability, language)},
                {"role": "user", "content": text},
            ],
            "options": {"temperature": 0.2},
        }

        body = json.dumps(payload).encode("utf-8")
        req = request.Request(
            f"{self.base_url}/api/chat",
            data=body,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            method="POST",
        )

        with request.urlopen(req, timeout=self.request_timeout) as response:
            raw = response.read().decode("utf-8") or "{}"
        return json.loads(raw)

    def process_one_job(self) -> None:
        next_path = self.next_job_file()
        if next_path is None:
            return

        claimed = self.claim_job(next_path)
        request_id = claimed.stem.replace(".processing", "")
        self.state.active_job = request_id
        self.write_state()

        try:
            job = read_json(claimed)
        except Exception as exc:
            self.state.processed_total += 1
            self.state.failed_total += 1
            self.state.last_job_id = request_id
            self.state.last_completed_at = utc_now()
            self.state.last_error = f"{request_id}: JSON invalido: {exc}"
            atomic_write_json(
                self.outbound_path_for(request_id),
                {
                    "id": request_id,
                    "status": "failed",
                    "error": f"JSON invalido: {exc}",
                    "completed_at": self.state.last_completed_at,
                },
            )
            self.archive_job(claimed, "invalid")
            self.state.active_job = None
            self.write_state()
            return

        text = str(job.get("text") or "")
        capability = str(job.get("capability") or "grammar_review")
        language = job.get("language")
        model = job.get("model")
        metadata = job.get("metadata") if isinstance(job.get("metadata"), dict) else {}
        request_id = str(job.get("id") or request_id)

        if not text.strip():
            error_message = "campo 'text' vazio"
            self.state.processed_total += 1
            self.state.failed_total += 1
            self.state.last_job_id = request_id
            self.state.last_completed_at = utc_now()
            self.state.last_error = f"{request_id}: {error_message}"
            atomic_write_json(
                self.outbound_path_for(request_id),
                {
                    "id": request_id,
                    "status": "failed",
                    "error": error_message,
                    "capability": capability,
                    "completed_at": self.state.last_completed_at,
                    "metadata": metadata,
                },
            )
            self.archive_job(claimed, "invalid")
            self.state.active_job = None
            self.write_state()
            return

        try:
            response_payload = self.call_ollama(
                capability=capability,
                text=text,
                language=str(language) if language else None,
                model=str(model) if model else None,
            )
            result_text = str(response_payload.get("message", {}).get("content") or "").strip()
            if not result_text:
                raise ValueError("resposta vazia do Ollama")

            self.state.processed_total += 1
            self.state.succeeded_total += 1
            self.state.last_job_id = request_id
            self.state.last_completed_at = utc_now()
            self.state.last_error = None

            atomic_write_json(
                self.outbound_path_for(request_id),
                {
                    "id": request_id,
                    "status": "succeeded",
                    "capability": capability,
                    "model": model or self.default_model,
                    "provider": "ollama",
                    "text": text,
                    "result": result_text,
                    "metadata": metadata,
                    "usage": {
                        "tokens_in": response_payload.get("prompt_eval_count"),
                        "tokens_out": response_payload.get("eval_count"),
                    },
                    "completed_at": self.state.last_completed_at,
                },
            )
            self.archive_job(claimed, "processed")
        except Exception as exc:
            self.state.processed_total += 1
            self.state.failed_total += 1
            self.state.last_job_id = request_id
            self.state.last_completed_at = utc_now()
            self.state.last_error = f"{request_id}: {exc}"
            atomic_write_json(
                self.outbound_path_for(request_id),
                {
                    "id": request_id,
                    "status": "failed",
                    "capability": capability,
                    "model": model or self.default_model,
                    "provider": "ollama",
                    "text": text,
                    "metadata": metadata,
                    "error": str(exc),
                    "completed_at": self.state.last_completed_at,
                },
            )
            self.archive_job(claimed, "failed")
        finally:
            self.state.active_job = None
            self.write_state()


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "serve"
    watcher = AirchWatcher()

    if mode == "serve":
        watcher.refresh_status()
        watcher.run()
        return 0

    if mode in {"once", "status"}:
        payload = watcher.refresh_status()
        sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
        return 0

    if mode == "waybar":
        if watcher.waybar_file.exists():
            sys.stdout.write(watcher.waybar_file.read_text(encoding="utf-8").strip() + "\n")
            return 0
        payload = watcher.refresh_status()
        sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
        return 0

    sys.stderr.write("usage: airch_watcher.py [serve|once|status|waybar]\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
