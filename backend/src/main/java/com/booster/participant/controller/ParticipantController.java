package com.booster.participant.controller;

import com.booster.participant.dto.ParticipantResponse;
import com.booster.participant.dto.ParticipationRequest;
import com.booster.participant.service.ParticipationService;
import com.booster.shared.common.ApiResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/challenges")
@RequiredArgsConstructor
public class ParticipantController {

    private final ParticipationService participationService;

    @PostMapping("/{challengeId}/participants")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<ParticipantResponse> apply(
            @RequestHeader("X-User-Id") Long userId,
            @PathVariable Long challengeId,
            @Valid @RequestBody ParticipationRequest request) {
        return ApiResponse.success(participationService.requestParticipation(userId, challengeId, request));
    }

    @DeleteMapping("/{challengeId}/participants/{targetUserId}")
    public ApiResponse<Void> cancel(
            @RequestHeader("X-User-Id") Long userId,
            @PathVariable Long challengeId,
            @PathVariable Long targetUserId) {
        participationService.cancelParticipation(userId, challengeId);
        return ApiResponse.success("Participation cancelled", null);
    }

    @PostMapping("/{challengeId}/participants/{participantId}/approve")
    public ApiResponse<ParticipantResponse> approve(
            @RequestHeader("X-User-Id") Long leaderId,
            @PathVariable Long challengeId,
            @PathVariable Long participantId) {
        return ApiResponse.success(participationService.approveParticipation(leaderId, challengeId, participantId));
    }
}
