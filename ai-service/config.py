import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
ANTHROPIC_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
PORT = int(os.environ.get("PORT", "8000"))

BASE_DIR = Path(__file__).parent
STORAGE_DIR = BASE_DIR / "storage"

MAX_IMAGE_BYTES = 10 * 1024 * 1024
