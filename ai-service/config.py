import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
ANTHROPIC_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
PORT = int(os.environ.get("PORT", "8000"))

#: 판정 한 건이 낼 수 있는 출력 상한. `PhotoVerdict` 는 짧아서 512로 충분하지만,
#: 기준을 길게 쓰거나 reason 을 늘리는 튜닝을 하면 여기가 먼저 막힌다.
ANTHROPIC_MAX_TOKENS = int(os.environ.get("ANTHROPIC_MAX_TOKENS", "512"))

#: backend `AiVerificationClient` 가 30초에 끊는다. **안쪽인 여기가 먼저 끊어져야**
#: 502 "AI 판정 실패" 사유가 남고 backend 가 재시도 가능한 실패로 번역한다.
#: 30초로 맞춰 두면 어느 쪽이 먼저 터질지 경합이라 그 사유가 사라진다.
ANTHROPIC_TIMEOUT_SECONDS = float(os.environ.get("ANTHROPIC_TIMEOUT_SECONDS", "25.0"))

BASE_DIR = Path(__file__).parent
STORAGE_DIR = BASE_DIR / "storage"

#: 판정 정책 파일(`verification.yaml`)이 놓인 디렉터리.
#:
#: 판정 기준은 코드가 아니라 제품 정책이다. 운영에서 여기에 볼륨을 마운트하면
#: 이미지를 다시 굽지 않고 기준만 갈아끼울 수 있다 — 이 환경변수가 외부화의 핵심이다.
POLICY_DIR = Path(os.environ.get("POLICY_DIR") or BASE_DIR / "policies")

MAX_IMAGE_MB = int(os.environ.get("MAX_IMAGE_MB", "10"))
MAX_IMAGE_BYTES = MAX_IMAGE_MB * 1024 * 1024

#: Pillow 가 알아낸 포맷 → Anthropic 에 실어 보낼 media type.
#: 이 표에 없는 포맷은 415다. 포맷 판별을 확장자·Content-Type 이 아니라 실제
#: 바이트로 하는 이유는 클라이언트가 보낸 이름을 믿을 수 없어서다.
ALLOWED_IMAGE_MEDIA_TYPES = {
    "JPEG": "image/jpeg",
    "PNG": "image/png",
    "WEBP": "image/webp",
}
