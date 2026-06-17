package com.booster.social.controller;

import com.booster.shared.common.ApiResponse;
import com.booster.social.dto.*;
import com.booster.social.service.CheerService;
import com.booster.social.service.LeaderboardService;
import com.booster.social.service.TeamChatService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequiredArgsConstructor
public class SocialController {

    private final LeaderboardService leaderboardService;
    private final TeamChatService teamChatService;
    private final CheerService cheerService;

    @GetMapping("/api/challenges/{challengeId}/leaderboards")
    public ApiResponse<List<LeaderboardEntry>> getLeaderboard(
            @PathVariable Long challengeId,
            @RequestParam String type) {
        List<LeaderboardEntry> entries;
        if ("TEAM".equalsIgnoreCase(type)) {
            entries = leaderboardService.getTeamLeaderboard(challengeId);
        } else {
            entries = leaderboardService.getPersonalLeaderboard(challengeId);
        }
        return ApiResponse.success(entries);
    }

    @GetMapping("/api/teams/{teamId}/chat")
    public ApiResponse<Page<ChatMessageResponse>> getMessages(
            @PathVariable Long teamId,
            Pageable pageable) {
        return ApiResponse.success(teamChatService.getMessages(teamId, pageable));
    }

    @PostMapping("/api/teams/{teamId}/chat")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<ChatMessageResponse> sendMessage(
            @RequestHeader("X-User-Id") Long senderId,
            @PathVariable Long teamId,
            @Valid @RequestBody SendMessageRequest request) {
        return ApiResponse.success(teamChatService.sendMessage(senderId, teamId, request.getContent()));
    }

    @DeleteMapping("/api/teams/{teamId}/chat/{messageId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteMessage(
            @RequestHeader("X-User-Id") Long senderId,
            @PathVariable Long teamId,
            @PathVariable Long messageId) {
        teamChatService.deleteMessage(senderId, teamId, messageId);
    }

    @PostMapping("/api/challenges/{challengeId}/cheers")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<CheerEmojiResponse> sendCheer(
            @RequestHeader("X-User-Id") Long fromParticipantId,
            @PathVariable Long challengeId,
            @Valid @RequestBody CheerEmojiRequest request) {
        return ApiResponse.success(cheerService.sendCheer(
                challengeId, fromParticipantId,
                request.getToParticipantId(), request.getEmojiType()));
    }
}
