import base64
import json
from abc import ABC, abstractmethod

from anthropic import AsyncAnthropic

from prompts import build_prompt
from schemas import Category, VerificationResult


class Verifier(ABC):
    @abstractmethod
    async def verify(
        self,
        image_bytes: bytes,
        media_type: str,
        category: Category,
    ) -> VerificationResult:
        ...


class AnthropicVerifier(Verifier):
    def __init__(self, api_key: str, model: str) -> None:
        self.client = AsyncAnthropic(api_key=api_key)
        self.model = model

    async def verify(
        self,
        image_bytes: bytes,
        media_type: str,
        category: Category,
    ) -> VerificationResult:
        image_b64 = base64.standard_b64encode(image_bytes).decode("ascii")
        prompt = build_prompt(category)

        message = await self.client.messages.create(
            model=self.model,
            max_tokens=512,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": image_b64,
                            },
                        },
                        {"type": "text", "text": prompt},
                    ],
                }
            ],
        )

        text = message.content[0].text if message.content else ""
        payload = _parse_json_response(text)

        return VerificationResult(
            passed=bool(payload.get("passed", False)),
            confidence_score=float(payload.get("confidence_score", 0.0)),
            detected_labels=list(payload.get("detected_labels", [])),
            reason=str(payload.get("reason", "")),
            model_name=self.model,
            raw_response=payload,
        )


def _parse_json_response(text: str) -> dict:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("```", 2)[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {
            "passed": False,
            "confidence_score": 0.0,
            "detected_labels": [],
            "reason": f"응답 파싱 실패: {text[:200]}",
        }
