package com.booster.challengecheckin.dto;

import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.domain.CheckInStatus;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Getter
@Builder
public class CheckInResponse {

    private Long id;
    private Long participantId;
    private LocalDate checkInDate;
    private CheckInStatus status;
    private LocalDateTime verifiedAt;

    /**
     * 이번 체크인으로 생성된 인증 제출 id. AI 인증 2단계 호출
     * ({@code POST /api/verification-submissions/{submissionId}/ai-verification})의 입력이다.
     *
     * <p>이 값이 없던 시절 클라이언트는 submissionId 를 얻을 방법이 아예 없었다 — 조회 API 도
     * 없고, submissionId 가 나오는 곳은 AI 인증 <b>결과</b> 응답뿐이라 순환이었다. 그 결과
     * AI 사진 인증 흐름을 앱에서 시작할 수 없었다.
     *
     * <p>목록 조회({@code GET .../check-ins})처럼 제출을 새로 만들지 않는 응답에서는 null 이다.
     */
    private Long submissionId;

    public static CheckInResponse from(ChallengeCheckIn checkIn) {
        return from(checkIn, null);
    }

    public static CheckInResponse from(ChallengeCheckIn checkIn, Long submissionId) {
        return CheckInResponse.builder()
                .id(checkIn.getId())
                .participantId(checkIn.getParticipantId())
                .checkInDate(checkIn.getCheckInDate())
                .status(checkIn.getStatus())
                .verifiedAt(checkIn.getVerifiedAt())
                .submissionId(submissionId)
                .build();
    }
}
