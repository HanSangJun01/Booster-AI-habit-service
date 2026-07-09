package com.booster.social.dto;

import com.booster.social.domain.ChatMessage;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class ChatMessageResponse {

    private Long id;
    private Long teamId;
    private Long senderId;
    private String content;
    private LocalDateTime createdAt;

    public static ChatMessageResponse from(ChatMessage m) {
        return ChatMessageResponse.builder()
                .id(m.getId())
                .teamId(m.getTeamId())
                .senderId(m.getSenderId())
                .content(m.getContent())
                .createdAt(m.getCreatedAt())
                .build();
    }
}
