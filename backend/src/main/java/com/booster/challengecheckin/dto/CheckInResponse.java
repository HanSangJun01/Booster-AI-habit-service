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

    public static CheckInResponse from(ChallengeCheckIn checkIn) {
        return CheckInResponse.builder()
                .id(checkIn.getId())
                .participantId(checkIn.getParticipantId())
                .checkInDate(checkIn.getCheckInDate())
                .status(checkIn.getStatus())
                .verifiedAt(checkIn.getVerifiedAt())
                .build();
    }
}
