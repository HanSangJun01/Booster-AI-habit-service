package com.booster.personalcheckin.dto;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 오늘 인증 상태. 레코드가 없으면 status = "NOT_CHECKED".
 *
 * @param checkInId 오늘 체크인의 id. 레코드가 없으면 null.
 *                  <p>사진 인증 경로({@code POST /api/personal/check-in/{checkInId}/ai-verification})가
 *                  이 값을 요구한다. 예전에는 이 응답에 없어서, 앱이 체크인 직후 메모리에 들고 있던
 *                  id 로만 사진을 올릴 수 있었다. 그래서 <b>GPS 인증만 하고 앱을 껐다 켜면
 *                  PENDING 인 채로 사진을 올릴 방법이 사라졌다</b> — 다시 체크인하려 해도 하루 1건
 *                  제한(409)에 막혀 그날은 아무것도 할 수 없었다.
 */
public record TodayStatusResponse(
        LocalDate date,
        String status,
        OffsetDateTime verifiedAt,
        Long checkInId
) {
}
