"""판정 정책 파일 로더.

## 왜 파일인가

판정 기준("무엇을 운동으로 인정하는가")은 코드가 아니라 **제품 정책**이다.
소스 문자열로 두면 오판 하나를 고치는 데 코드 수정 → Docker 재빌드 → 재배포가
필요했다. 정책을 `policies/verification.yaml` 로 빼면 운영에서 `POLICY_DIR` 에
볼륨을 마운트해 기준만 갈아끼울 수 있다.

## 왜 기동 시 한 번만 읽는가

핫리로드는 일부러 만들지 않았다. 판정 도중 기준이 바뀌면 같은 사진이 다른 판정을
받고, 어떤 기준으로 내려진 판정인지 되짚을 수 없다. 정책 교체는 재기동으로 한다.

## 왜 실패를 임포트 시점으로 당기는가

예전엔 `_CATEGORY_CRITERIA[category]` 가 맨 dict 조회였다. `Category` 에 값만
늘리고 기준을 빠뜨리면 **그 카테고리로 첫 요청이 들어오는 순간** KeyError → 500이
났다. 여기서는 파일이 깨졌거나 카테고리가 어긋나면 프로세스가 아예 안 뜬다.
배포가 실패하는 편이 사용자가 500을 받는 것보다 낫다.
"""

from dataclasses import dataclass
from pathlib import Path

import yaml

import config

POLICY_FILENAME = "verification.yaml"


class PolicyError(RuntimeError):
    """정책 파일을 신뢰할 수 없다. 기동을 멈추는 것이 목적인 예외다."""


@dataclass(frozen=True)
class VerificationPolicy:
    """`verification.yaml` 한 벌. 값은 전부 **모델에게 가는 문구**다."""

    path: Path
    system: str
    instruction_template: str
    output_description: str
    output_fields: dict[str, str]
    categories: dict[str, str]

    def criteria(self, category: str) -> str:
        """카테고리 판정 기준. 없으면 dict 조회 대신 사유가 붙은 예외를 던진다."""
        try:
            return self.categories[category]
        except KeyError:
            raise PolicyError(
                f"{self.path}: 카테고리 '{category}' 의 판정 기준이 없다. "
                f"정의된 카테고리: {sorted(self.categories)}"
            ) from None

    def field_description(self, field: str) -> str:
        """`PhotoVerdict` 한 필드의 설명. 이것도 도구 스키마로 모델에 실려 간다."""
        try:
            return self.output_fields[field]
        except KeyError:
            raise PolicyError(
                f"{self.path}: output_fields 에 '{field}' 설명이 없다. "
                f"정의된 필드: {sorted(self.output_fields)}"
            ) from None

    def require_category_coverage(self, known: set[str]) -> None:
        """정책 파일의 카테고리와 코드의 `Category` 가 같은 집합인지 확인한다.

        양방향으로 본다. 코드에만 있으면 그 카테고리 요청이 500이 되고,
        파일에만 있으면 아무도 쓰지 않는 기준을 튜닝하며 왜 안 먹히는지 헤맨다.
        """
        missing = sorted(known - self.categories.keys())
        extra = sorted(self.categories.keys() - known)
        if not missing and not extra:
            return

        problems = []
        if missing:
            problems.append(
                f"코드 Category 에는 있지만 정책 파일에 기준이 없음: {missing}"
            )
        if extra:
            problems.append(
                f"정책 파일에는 있지만 코드 Category 에 없음: {extra}"
            )
        raise PolicyError(
            f"{self.path}: 카테고리 정합성 실패 — " + " / ".join(problems)
            + ". schemas.py::Category 와 정책 파일의 categories 를 함께 고쳐라."
        )


def _require_text(data: dict, key: str, path: Path) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise PolicyError(f"{path}: '{key}' 는 비어 있지 않은 문자열이어야 한다 (현재: {value!r})")
    return value


def _require_text_map(data: dict, key: str, path: Path) -> dict[str, str]:
    value = data.get(key)
    if not isinstance(value, dict) or not value:
        raise PolicyError(f"{path}: '{key}' 는 비어 있지 않은 매핑이어야 한다 (현재: {value!r})")
    for name, text in value.items():
        if not isinstance(text, str) or not text.strip():
            raise PolicyError(
                f"{path}: '{key}.{name}' 은 비어 있지 않은 문자열이어야 한다 (현재: {text!r})"
            )
    return dict(value)


def load(prompt_dir: Path | None = None) -> VerificationPolicy:
    """정책 파일을 읽어 검증한다. 인자는 테스트가 다른 정책을 물릴 때만 쓴다."""
    path = (prompt_dir or config.POLICY_DIR) / POLICY_FILENAME
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise PolicyError(
            f"판정 정책 파일을 읽을 수 없다: {path} ({exc}). "
            f"POLICY_DIR 환경변수가 정책 디렉터리를 가리키는지 확인하라."
        ) from exc

    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        raise PolicyError(f"{path}: YAML 파싱 실패 — {exc}") from exc

    if not isinstance(data, dict):
        raise PolicyError(f"{path}: 최상위는 매핑이어야 한다 (현재: {type(data).__name__})")

    instruction_template = _require_text(data, "instruction_template", path)
    if "{criteria}" not in instruction_template:
        raise PolicyError(
            f"{path}: instruction_template 에 {{criteria}} 자리가 없다 — "
            f"카테고리 기준이 모델에게 전달되지 않는다."
        )

    return VerificationPolicy(
        path=path,
        system=_require_text(data, "system", path),
        instruction_template=instruction_template,
        output_description=_require_text(data, "output_description", path),
        output_fields=_require_text_map(data, "output_fields", path),
        categories=_require_text_map(data, "categories", path),
    )


#: 기동 시 1회. 임포트에 실패하면 프로세스가 안 뜬다 — 그게 의도다.
POLICY = load()
