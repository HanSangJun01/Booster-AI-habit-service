package com.booster.challengecheckin.controller;

import com.booster.challengecheckin.dto.CheckInRequest;
import com.booster.challengecheckin.dto.CheckInResponse;
import com.booster.challengecheckin.dto.TeamDetailResponse;
import com.booster.challengecheckin.service.ChallengeCheckInService;
import com.booster.challengecheckin.service.TeamDetailViewService;
import com.booster.shared.checkin.CheckInOrchestrator;
import com.booster.shared.common.ApiResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;

@RestController
@RequestMapping("/api/challenges")
@RequiredArgsConstructor
public class ChallengeCheckInController {

    private final CheckInOrchestrator checkInOrchestrator;
    private final ChallengeCheckInService challengeCheckInService;
    private final TeamDetailViewService teamDetailViewService;

    @PostMapping("/{challengeId}/check-ins")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<CheckInResponse> checkIn(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long challengeId,
            @Valid @RequestBody CheckInRequest request) {
        CheckInResponse response = checkInOrchestrator.performCheckIn(
                userId, challengeId, request.getCurrentLat(), request.getCurrentLng());
        return ApiResponse.success(response);
    }

    @GetMapping("/{challengeId}/check-ins")
    public ApiResponse<List<CheckInResponse>> getTeamCheckIns(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long challengeId,
            @RequestParam(required = false) @DateTimeFormat(pattern = "yyyyMMdd") LocalDate date) {
        // (BS-39 I14) 비참여자의 타 챌린지 체크인 현황 열람 차단 — 서비스에서 멤버십 검증.
        LocalDate targetDate = date != null ? date : LocalDate.now(ZoneId.of("Asia/Seoul"));
        return ApiResponse.success(challengeCheckInService.getTeamCheckIns(userId, challengeId, targetDate));
    }

    @GetMapping("/{challengeId}/team-detail")
    public ApiResponse<TeamDetailResponse> getTeamDetail(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long challengeId) {
        return ApiResponse.success(teamDetailViewService.getTeamComparison(challengeId, userId));
    }
}
