import logging
import time
from abc import ABC, abstractmethod
from pathlib import Path

logger = logging.getLogger(__name__)


class Storage(ABC):
    @abstractmethod
    async def save(self, key: str, content: bytes) -> str:
        """Persist content under key. Return a storage-scoped identifier."""

    @abstractmethod
    async def load(self, key: str) -> bytes:
        ...


class LocalStorage(Storage):
    def __init__(self, base_dir: Path) -> None:
        self.base_dir = base_dir
        self.base_dir.mkdir(parents=True, exist_ok=True)

    async def save(self, key: str, content: bytes) -> str:
        path = self.base_dir / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return str(path.relative_to(self.base_dir.parent))

    async def load(self, key: str) -> bytes:
        path = self.base_dir / key
        return path.read_bytes()

    def purge_older_than(self, days: int) -> int:
        """보존 기간이 지난 파일을 지우고 삭제 수를 돌려준다.

        인증 사진은 얼굴·집 내부·위치가 드러나는 개인정보라 무기한 보관하지
        않는다. 기준은 파일 mtime — 저장 이후 손대지 않는 파일들이라 저장 시각과
        같다. `days<=0` 이면 아무것도 하지 않는다(끔).
        """
        if days <= 0:
            return 0
        cutoff = time.time() - days * 86400
        removed = 0
        for path in self.base_dir.rglob("*"):
            if not path.is_file():
                continue
            try:
                if path.stat().st_mtime < cutoff:
                    path.unlink()
                    removed += 1
            except OSError as exc:
                # 한 파일이 안 지워진다고 purge 전체를 멈추지 않는다.
                logger.warning("보존기간 purge 실패: %s (%s)", path, exc)
        if removed:
            logger.info("보존기간(%d일) 경과 이미지 %d건 삭제", days, removed)
        return removed
