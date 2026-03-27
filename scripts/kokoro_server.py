"""
Kokoro TTS FastAPI Server — OpenAI-compatible endpoint.

Provides:
  POST /v1/audio/speech  → generates audio (OpenAI TTS format)
  GET  /v1/voices        → lists available voices per language
  GET  /health           → health check

Usage:
  uvicorn kokoro_server:app --host 0.0.0.0 --port 8880

Requires: pip install fastapi uvicorn
Kokoro must already be installed in the environment.
"""

import io
import subprocess
import tempfile
from contextlib import asynccontextmanager
from typing import Optional

import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

# Language code mapping for Kokoro
LANG_MAP = {
    "pt-BR": "p", "pt": "p",
    "en-US": "a", "en": "a", "en-GB": "b",
    "zh-CN": "z", "zh": "z", "zh-TW": "z",
    "ja-JP": "j", "ja": "j",
    "ko-KR": "k", "ko": "k",
    "es-ES": "e", "es": "e",
    "fr-FR": "f", "fr": "f",
    "it-IT": "i", "it": "i",
    "hi-IN": "h", "hi": "h",
}

# Default voices per language code
DEFAULT_VOICES = {
    "p": "pf_dora",
    "a": "af_heart",
    "b": "bf_emma",
    "z": "zf_xiaobei",
    "j": "jf_alpha",
    "k": "kf_yuha",
    "e": "ef_dora",
    "f": "ff_siwis",
    "i": "if_sara",
    "h": "hf_alpha",
}

# Voice catalog per language
VOICE_CATALOG = {
    "p": ["pf_dora", "pm_alex", "pm_santa"],
    "a": ["af_heart", "af_bella", "af_nicole", "am_adam", "am_michael"],
    "b": ["bf_emma", "bf_isabella", "bm_george", "bm_lewis"],
    "z": ["zf_xiaobei", "zf_xiaoni", "zf_xiaoxiao", "zm_yunjian", "zm_yunxi"],
    "j": ["jf_alpha", "jf_gongitsune", "jm_kumo"],
    "k": ["kf_yuha", "km_yongsu"],
    "e": ["ef_dora", "em_alex"],
    "f": ["ff_siwis"],
    "i": ["if_sara", "im_nicola"],
    "h": ["hf_alpha", "hf_beta", "hm_omega", "hm_psi"],
}

# Singleton pipeline cache
_pipelines = {}


def get_pipeline(lang_code: str):
    """Get or create a KPipeline for the given language code."""
    if lang_code not in _pipelines:
        from kokoro import KPipeline
        _pipelines[lang_code] = KPipeline(lang_code=lang_code)
    return _pipelines[lang_code]


def detect_lang_code(voice: str, language: Optional[str] = None) -> str:
    """Detect Kokoro language code from voice name or explicit language."""
    if language:
        code = LANG_MAP.get(language)
        if code:
            return code

    # Voice names start with language prefix: af_, pf_, zm_, etc.
    if voice and len(voice) >= 2:
        return voice[0]

    return "a"  # default to American English


def synthesize_wav(text: str, voice: str, lang_code: str, speed: float = 1.0) -> bytes:
    """Generate WAV audio bytes from text using Kokoro."""
    pipeline = get_pipeline(lang_code)
    generator = pipeline(text, voice=voice, speed=speed)

    chunks = []
    for _, _, audio in generator:
        chunks.append(audio)

    if not chunks:
        raise ValueError("Kokoro produced no audio output")

    audio_data = np.concatenate(chunks)

    buf = io.BytesIO()
    sf.write(buf, audio_data, 24000, format="WAV")
    buf.seek(0)
    return buf.read()


def wav_to_mp3(wav_bytes: bytes) -> bytes:
    """Convert WAV bytes to MP3 using ffmpeg."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as wav_file:
        wav_file.write(wav_bytes)
        wav_file.flush()

        result = subprocess.run(
            ["ffmpeg", "-y", "-i", wav_file.name, "-f", "mp3", "-ab", "192k", "-"],
            capture_output=True,
            timeout=60,
        )

        if result.returncode != 0:
            raise RuntimeError(f"ffmpeg failed: {result.stderr.decode()[:200]}")

        return result.stdout


def wav_to_opus(wav_bytes: bytes) -> bytes:
    """Convert WAV bytes to Opus using ffmpeg."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as wav_file:
        wav_file.write(wav_bytes)
        wav_file.flush()

        result = subprocess.run(
            ["ffmpeg", "-y", "-i", wav_file.name, "-f", "opus", "-b:a", "128k", "-"],
            capture_output=True,
            timeout=60,
        )

        if result.returncode != 0:
            raise RuntimeError(f"ffmpeg failed: {result.stderr.decode()[:200]}")

        return result.stdout


# --- FastAPI App ---

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Warm up default pipeline on startup
    try:
        get_pipeline("a")
    except Exception:
        pass
    yield
    _pipelines.clear()


app = FastAPI(title="Kokoro TTS Server", version="1.0.0", lifespan=lifespan)


class SpeechRequest(BaseModel):
    input: str
    voice: str = "af_heart"
    response_format: str = "mp3"
    speed: float = 1.0
    language: Optional[str] = None


CONTENT_TYPES = {
    "mp3": "audio/mpeg",
    "wav": "audio/wav",
    "opus": "audio/opus",
}


@app.post("/v1/audio/speech")
async def create_speech(req: SpeechRequest):
    if not req.input.strip():
        raise HTTPException(status_code=400, detail="Input text is empty")

    lang_code = detect_lang_code(req.voice, req.language)

    try:
        wav_bytes = synthesize_wav(req.input, req.voice, lang_code, req.speed)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Synthesis failed: {str(e)[:200]}")

    fmt = req.response_format.lower()
    if fmt == "wav":
        audio_bytes = wav_bytes
    elif fmt == "opus":
        audio_bytes = wav_to_opus(wav_bytes)
    else:
        audio_bytes = wav_to_mp3(wav_bytes)

    content_type = CONTENT_TYPES.get(fmt, "audio/mpeg")
    return Response(content=audio_bytes, media_type=content_type)


@app.get("/v1/voices")
async def list_voices():
    result = {}
    for lang_code, voices in VOICE_CATALOG.items():
        # Reverse map lang_code to language names
        lang_names = [k for k, v in LANG_MAP.items() if v == lang_code and "-" in k]
        for name in lang_names:
            result[name] = voices
    return {"voices": result}


@app.get("/health")
async def health():
    loaded_langs = list(_pipelines.keys())
    return {"status": "ok", "loaded_languages": loaded_langs}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8880)
