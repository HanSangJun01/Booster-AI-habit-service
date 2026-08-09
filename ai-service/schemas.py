from enum import Enum

from pydantic import BaseModel, Field


class Category(str, Enum):
    EXERCISE = "EXERCISE"
    STUDY = "STUDY"


class VerificationResult(BaseModel):
    passed: bool
    confidence_score: float = Field(ge=0.0, le=1.0)
    detected_labels: list[str]
    model_name: str
    reason: str
    storage_key: str | None = None
    raw_response: dict | None = None
