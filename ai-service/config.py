import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
ANTHROPIC_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
PORT = int(os.environ.get("PORT", "8000"))

#: 판정 엔드포인트 공유 시크릿. 설정하면 `/verify*` 요청은 `X-API-Key` 헤더가
#: 이 값과 일치해야 한다. 비워 두면 검사하지 않는다(로컬 개발용) — 운영에서
#: 비워 두면 이 서비스가 곧 "당신 Anthropic 키의 공짜 프록시"다. 반드시 설정하라.
AI_SERVICE_API_KEY = os.environ.get("AI_SERVICE_API_KEY", "")

#: IP당 분당 판정 요청 상한. 0이면 끔. 판정 한 건이 실제 과금되는 모델 호출이라
#: 인증과 별개로 상한이 필요하다 — 시크릿이 새더라도 폭주 비용을 막는 마지막 둑.
#: 프로세스 메모리 기반이므로 멀티 워커(uvicorn --workers N)에서는 워커당 N배가
#: 된다. 그 배치로 가면 리버스 프록시(nginx limit_req 등)로 옮겨라.
RATE_LIMIT_PER_MINUTE = int(os.environ.get("RATE_LIMIT_PER_MINUTE", "30"))

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

#: EXIF 촬영시각(DateTimeOriginal)이 이보다 오래된 사진은 모델을 부르지 않고
#: 즉시 반려한다. 0이면 끔. EXIF 가 아예 없는 사진은 **통과시켜 모델로 보낸다** —
#: 메신저·스크린샷·일부 카메라 앱이 EXIF 를 벗겨내므로, 없음을 거절 사유로 삼으면
#: 정상 사용자가 대거 반려된다. EXIF 에는 타임존이 없어 서버 로컬시각과의 비교는
#: 최대 ±14시간 오차가 있다 — 그래서 기본값을 여유 있게 48시간으로 둔다.
MAX_PHOTO_AGE_HOURS = int(os.environ.get("MAX_PHOTO_AGE_HOURS", "48"))

#: 저장된 인증 사진 보존 기간(일). 0이면 끔. 얼굴·집 내부·위치가 드러나는
#: 개인정보라 무기한 보관하지 않는다 — 기동 시 1회 + 24시간마다 이보다 오래된
#: 파일을 지운다.
STORAGE_RETENTION_DAYS = int(os.environ.get("STORAGE_RETENTION_DAYS", "30"))

#: Pillow 가 알아낸 포맷 → Anthropic 에 실어 보낼 media type.
#: 이 표에 없는 포맷은 415다. 포맷 판별을 확장자·Content-Type 이 아니라 실제
#: 바이트로 하는 이유는 클라이언트가 보낸 이름을 믿을 수 없어서다.
ALLOWED_IMAGE_MEDIA_TYPES = {
    "JPEG": "image/jpeg",
    "PNG": "image/png",
    "WEBP": "image/webp",
}
