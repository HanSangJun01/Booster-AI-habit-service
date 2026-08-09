package com.booster.challengecheckin.dto;

import com.booster.challengecheckin.domain.CheckInStatus;
import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class TeamMemberCheckInStatus {

    private Long userId;
    private Long participantId;
    private boolean checkedIn;
    private CheckInStatus status;
}
