/// 챌린지 카테고리 — **화면에 보이는 이름과 서버로 보내는 값이 다르다.**
///
/// ## 왜 분리하나
/// 백엔드는 `challenges.category`를 자유 문자열로 받아 검증 없이 그대로
/// `ai-service`에 넘긴다. 그런데 `ai-service`의 카테고리는 `EXERCISE` /
/// `STUDY` 두 값만 받는 Pydantic Enum이다.
///
/// 그래서 앱이 한글("운동")을 보내면 생성·참여·체크인까지 전부 통과한 뒤
/// **사진 업로드 단계에서 500**이 난다(백엔드가 upstream 4xx를 계약 오류로 보고
/// 500으로 바꾼다). 즉 AI 인증 챌린지가 하나도 작동하지 않는다.
///
/// 맞추는 쪽은 앱이다 — MVP 범위를 넓히지 않으려고 `ai-service`의 2종을
/// 유지하기로 확정했다(계획서 §4.1, 2026-08-27).
///
/// ## 두 값에 넷을 욱여넣은 결과
/// [reading]이 [study]와 **같은 값**(`STUDY`)으로 나간다. `ai-service` 프롬프트의
/// STUDY 통과 기준에 활자책 독서가 이미 들어 있어서 판정은 맞지만, 저장된
/// 뒤에는 공부와 독서를 구분할 수 없다. 그래서 목록에 이름을 되비출 때는
/// [labelOf]가 '공부·독서'로 묶어 보여준다 — 독서 챌린지를 '공부'라고 단정하지
/// 않기 위해서다.
///
/// ## [2026-09] 고를 수 있는 건 운동·공부 둘뿐이다
/// 서버가 `category`를 `EXERCISE`/`STUDY` 로 검증하기 시작했다. 그래서
/// [reading]과 [wakeUp]은 **선택지에서 뺐다**:
///   · 독서는 [study]와 전송값이 같아 따로 둘 이유가 없다(공부로 합쳤다)
///   · 기상은 사진 판정 기준이 없어(`WAKE_UP`) 이제 400 으로 거절된다
///
/// enum 값 자체는 남겨 둔다 — 이 변경 전에 만들어진 챌린지가 그 값을 들고 있어서
/// 목록·상세를 그릴 때 [labelOf]가 읽어야 한다.
enum ChallengeCategory {
  exercise(label: '운동', value: 'EXERCISE', aiValue: 'EXERCISE'),
  study(label: '공부', value: 'STUDY', aiValue: 'STUDY'),
  reading(label: '독서', value: 'STUDY', aiValue: 'STUDY'),
  wakeUp(label: '기상', value: 'WAKE_UP', aiValue: null);

  /// 선택지에 보이는 이름. 서버로 나가지 않는다.
  final String label;

  /// 챌린지를 만들 때 `category`로 보내는 값.
  final String value;

  /// 사진 업로드(`ai-verification`)의 `category`로 보낼 값.
  ///
  /// null이면 AI 판정을 맡길 수 없는 카테고리다 — 보낼 어휘가 없어서 무엇을
  /// 보내든 500이 난다.
  final String? aiValue;

  const ChallengeCategory({
    required this.label,
    required this.value,
    required this.aiValue,
  });

  /// 생성 화면의 선택지. 서버가 받는 두 값뿐이다.
  ///
  /// 독서는 [study]와 전송값이 같아 합쳤고, 기상은 사진 판정 기준이 없어 서버가
  /// 400 으로 거절한다.
  static const choices = [exercise, study];

  /// 탐색 필터의 선택지. 만들 수 있는 것과 같은 두 종류다.
  static const filters = [exercise, study];

  /// 서버에 저장된 값을 화면에 쓸 이름으로 바꾼다.
  ///
  /// 사진 업로드에 실어 보낼 카테고리. 못 보낼 값이면 null이다.
  ///
  /// 챌린지의 `category`를 그대로 넘기면 안 된다 — 자유 문자열이라 `WAKE_UP`이나
  /// 옛 한글("독서")이 들어 있을 수 있고, 그러면 `ai-service`가 422를 주고
  /// 백엔드가 그걸 500 `AI_VERIFICATION_500`으로 바꾼다. 사용자 입력 실수가
  /// 서버 장애로 집계되는 경로다.
  ///
  /// 옛 한글 데이터도 받아준다. 이 변경 전에 만들어진 챌린지가 AI 인증을 쓰고
  /// 있을 수 있는데, 매핑을 포기하면 그 챌린지는 영영 인증을 못 끝낸다.
  static String? aiValueOf(String storedCategory) {
    switch (storedCategory) {
      case 'EXERCISE':
      case '운동':
        return exercise.aiValue;
      case 'STUDY':
      case '공부':
      case '독서':
        return study.aiValue;
      default:
        return null;
    }
  }

  /// 개인 트랙에서 사진 인증에 쓸 수 있는 선택지.
  ///
  /// 개인 트랙에는 **카테고리를 저장하는 컬럼이 아예 없다.** 그래서 업로드할
  /// 때마다 앱이 무엇을 인증하는지 지정해야 하고, 사용자에게 물을 수밖에 없다.
  /// 기상이 빠진 건 [aiValue]가 없어서다.
  static const photoChoices = [exercise, study, reading];

  /// 모르는 값은 그대로 돌려준다. 이 변경 이전에 만들어진 챌린지는 카테고리가
  /// 한글로 저장돼 있어서, 억지로 매핑하면 멀쩡한 이름이 빈칸이 된다.
  static String labelOf(String value) {
    switch (value) {
      case 'EXERCISE':
        return exercise.label;
      case 'STUDY':
        return '공부·독서';
      case 'WAKE_UP':
        return wakeUp.label;
      default:
        return value;
    }
  }
}
