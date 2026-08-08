from abc import ABC, abstractmethod
from pathlib import Path


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
