package com.booster.social.service;

import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.UnauthorizedException;
import com.booster.social.domain.ChatMessage;
import com.booster.social.dto.ChatMessageResponse;
import com.booster.social.repository.ChatMessageRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@Transactional
@RequiredArgsConstructor
public class TeamChatService {

    private final ChatMessageRepository chatMessageRepository;
    private final ChallengeParticipantRepository participantRepository;

    @Transactional(readOnly = true)
    public Page<ChatMessageResponse> getMessages(Long userId, Long teamId, Pageable pageable) {
        // (BS-39 I2) 읽기에도 멤버십 검사 — 이전엔 검사가 없어 비참여자가 남의 팀 채팅을 통째로 읽었다.
        // (쓰기엔 이미 있었다). 팀 멤버가 아니면 403.
        assertMember(userId, teamId);
        return chatMessageRepository
                .findByTeamIdAndDeletedAtIsNullOrderByCreatedAtDesc(teamId, pageable)
                .map(ChatMessageResponse::from);
    }

    public ChatMessageResponse sendMessage(Long senderId, Long teamId, String content) {
        assertMember(senderId, teamId);

        ChatMessage message = ChatMessage.builder()
                .teamId(teamId)
                .senderId(senderId)
                .content(content)
                .build();

        ChatMessageResponse response = ChatMessageResponse.from(chatMessageRepository.save(message));
        log.info("Chat message sent: teamId={}, userId={}", teamId, senderId);
        return response;
    }

    public void deleteMessage(Long senderId, Long teamId, Long messageId) {
        ChatMessage message = chatMessageRepository.findById(messageId)
                .orElseThrow(() -> new com.booster.shared.common.ResourceNotFoundException("ChatMessage", messageId));

        if (!message.getTeamId().equals(teamId)) {
            throw new UnauthorizedException("Message does not belong to team " + teamId);
        }

        if (!message.getSenderId().equals(senderId)) {
            throw new UnauthorizedException("User " + senderId + " is not the sender of message " + messageId);
        }

        message.softDelete();
        chatMessageRepository.save(message);
        log.info("Chat message deleted: messageId={}, userId={}", messageId, senderId);
    }

    /** 해당 유저가 팀의 참여자인지 확인 — 아니면 403. 읽기/쓰기 공통 가드. */
    private void assertMember(Long userId, Long teamId) {
        boolean isMember = participantRepository.findByTeamId(teamId).stream()
                .anyMatch(p -> p.getUserId().equals(userId));
        if (!isMember) {
            log.warn("Unauthorized chat access: userId={}, teamId={}", userId, teamId);
            throw new UnauthorizedException("User " + userId + " is not a member of team " + teamId);
        }
    }
}
