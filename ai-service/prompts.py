"""모델에게 보낼 문구 조립.

문구 자체는 여기 없다 — `policies/verification.yaml` 에 있고 [`policy`] 가 읽는다.
이 모듈은 읽어 온 정책을 카테고리별 메시지로 엮기만 한다. 왜 파일로 뺐는지는
[`policy`] 의 모듈 문서를 봐라.

데이터 디렉터리 이름이 `prompts/` 가 아니라 `policies/` 인 이유: 이 모듈과 이름이
같으면 누군가 `prompts/__init__.py` 를 만드는 순간 패키지가 모듈을 가려 임포트가
터진다. 파이썬이 정규 모듈을 먼저 고르므로 당장은 동작했지만, 한 글자 차이로
망가지는 배치를 남길 이유가 없어 디렉터리 쪽 이름을 바꿨다.
"""

from policy import POLICY
from schemas import Category

#: 카테고리와 무관한 판별기 역할·판단 원칙. 시스템 메시지로 들어간다.
SYSTEM_PROMPT = POLICY.system


def build_instruction(category: Category) -> str:
    """이미지와 함께 보낼 카테고리별 판정 기준."""
    # `str.format` 이 아니라 replace 다. 기준 문구는 운영에서 손으로 고치는
    # 데이터라 중괄호가 섞일 수 있는데, format 이면 그 순간 KeyError 로 판정이
    # 통째로 죽는다. 치환할 자리는 하나뿐이니 replace 로 충분하다.
    criteria = POLICY.criteria(category.value)
    return POLICY.instruction_template.replace("{criteria}", criteria)
