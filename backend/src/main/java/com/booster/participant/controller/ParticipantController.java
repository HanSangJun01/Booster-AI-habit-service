package com.booster.participant.controller;

import com.booster.participant.dto.ParticipantResponse;
import com.booster.participant.dto.ParticipationRequest;
import com.booster.participant.service.ParticipationService;
import com.booster.shared.common.ApiResponse;
import com.booster.shared.common.UnauthorizedException;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import com.booster.participant.domain.ParticipantStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import java.util.List;

@RestController
@RequestMapping("/api/challenges")
@RequiredArgsConstructor
public class ParticipantController {

    private final ParticipationService participationService;

    @PostMapping("/{challengeId}/participants")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<ParticipantResponse> apply(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long challengeId,
            @Valid @RequestBody ParticipationRequest request) {
        return ApiResponse.success(participationService.requestParticipation(userId, challengeId, request));
    }

    /**
     * 참가자 목록. 방장 승인 화면이 {@code participantId} 를 얻는 유일한 경로다.
     * {@code ?status=PENDING} 으로 대기자만 걸러 볼 수 있다.
     */
    @GetMapping("/{challengeId}/participants")
    public ApiResponse<List<ParticipantResponse>> list(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long challengeId,
            @RequestParam(required = false) ParticipantStatus status) {
        return ApiResponse.success(participationService.getParticipants(userId, challengeId, status));
    }

    @DeleteMapping("/{challengeId}/participants/{targetUserId}")
    public ApiResponse<Void> cancel(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long challengeId,
            @PathVariable Long targetUserId) {
        if (!userId.equals(targetUserId)) {
            throw new UnauthorizedException("Cannot cancel another user's participation");
        }
        participationService.cancelParticipation(userId, challengeId);
        return ApiResponse.success("Participation cancelled", null);
    }

    @PostMapping("/{challengeId}/participants/{participantId}/approve")
    public ApiResponse<ParticipantResponse> approve(
            @AuthenticationPrincipal Long leaderId,
            @PathVariable Long challengeId,
            @PathVariable Long participantId) {
        return ApiResponse.success(participationService.approveParticipation(leaderId, challengeId, participantId));
    }
}
