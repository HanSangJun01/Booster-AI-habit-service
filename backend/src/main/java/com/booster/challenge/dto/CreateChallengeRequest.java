package com.booster.challenge.dto;

import com.booster.challenge.domain.ApprovalType;
import com.booster.challenge.domain.ChallengeVisibility;
import com.booster.challenge.domain.VerificationType;
import jakarta.validation.constraints.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class CreateChallengeRequest {

    @NotBlank
    private String category;

    @NotBlank
    @Size(max = 200)
    private String title;

    private String description;

    @NotNull
    private VerificationType verificationType;

    @Min(1)
    private int durationDays;

    @Min(0)
    private long depositCoins;

    @NotNull
    private ChallengeVisibility visibility;

    @NotNull
    private ApprovalType approvalType;

    @Min(2)
    @Max(10)
    private int maxParticipants = 10;
}
