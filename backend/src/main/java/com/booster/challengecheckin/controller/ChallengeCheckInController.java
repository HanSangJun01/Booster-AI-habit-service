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
            @RequestHeader("X-User-Id") Long userId,
            @PathVariable Long challengeId,
            @Valid @RequestBody CheckInRequest request) {
        CheckInResponse response = checkInOrchestrator.performCheckIn(
                userId, challengeId, request.getCurrentLat(), request.getCurrentLng());
        return ApiResponse.success(response);
    }

    @GetMapping("/{challengeId}/check-ins")
    public ApiResponse<List<CheckInResponse>> getTeamCheckIns(
            @PathVariable Long challengeId,
            @RequestParam(required = false) @DateTimeFormat(pattern = "yyyyMMdd") LocalDate date) {
        LocalDate targetDate = date != null ? date : LocalDate.now(ZoneId.of("Asia/Seoul"));
        return ApiResponse.success(challengeCheckInService.getTeamCheckIns(challengeId, targetDate));
    }

    @GetMapping("/{challengeId}/team-detail")
    public ApiResponse<TeamDetailResponse> getTeamDetail(
            @RequestHeader("X-User-Id") Long userId,
            @PathVariable Long challengeId) {
        return ApiResponse.success(teamDetailViewService.getTeamComparison(challengeId, userId));
    }
}
