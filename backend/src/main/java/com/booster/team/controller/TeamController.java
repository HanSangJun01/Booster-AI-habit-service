package com.booster.team.controller;

import com.booster.shared.common.ApiResponse;
import com.booster.team.dto.TeamResponse;
import com.booster.team.service.TeamFormationService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/challenges")
@RequiredArgsConstructor
public class TeamController {

    private final TeamFormationService teamFormationService;

    @GetMapping("/{challengeId}/teams")
    public ApiResponse<List<TeamResponse>> getTeams(@PathVariable Long challengeId) {
        return ApiResponse.success(teamFormationService.getTeams(challengeId));
    }
}
