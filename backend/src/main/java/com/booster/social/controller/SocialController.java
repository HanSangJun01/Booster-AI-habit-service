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
import org.springframework.security.core.annotation.AuthenticationPrincipal;
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
            @AuthenticationPrincipal Long userId,
            @PathVariable Long teamId,
            Pageable pageable) {
        // (BS-39 I2) 읽기에도 멤버십 검사가 필요하다(쓰기엔 이미 있었음). 예전엔 비참여자가
        // 임의 teamId로 남의 팀 채팅을 통째로 읽을 수 있었다. userId를 서비스로 넘겨 검증.
        return ApiResponse.success(teamChatService.getMessages(userId, teamId, pageable));
    }

    @PostMapping("/api/teams/{teamId}/chat")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<ChatMessageResponse> sendMessage(
            @AuthenticationPrincipal Long senderId,
            @PathVariable Long teamId,
            @Valid @RequestBody SendMessageRequest request) {
        return ApiResponse.success(teamChatService.sendMessage(senderId, teamId, request.getContent()));
    }

    @DeleteMapping("/api/teams/{teamId}/chat/{messageId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteMessage(
            @AuthenticationPrincipal Long senderId,
            @PathVariable Long teamId,
            @PathVariable Long messageId) {
        teamChatService.deleteMessage(senderId, teamId, messageId);
    }

    @PostMapping("/api/challenges/{challengeId}/cheers")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<CheerEmojiResponse> sendCheer(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long challengeId,
            @Valid @RequestBody CheerEmojiRequest request) {
        // [BS-A/B 통합] JWT principal은 userId다. cheer의 from은 participantId 공간이어야 하므로
        // userId를 그대로 넘기지 말고 CheerService에서 챌린지 참여자로 해석·검증한다(chat 패턴과 동일).
        return ApiResponse.success(cheerService.sendCheer(
                challengeId, userId,
                request.getToParticipantId(), request.getEmojiType()));
    }
}
