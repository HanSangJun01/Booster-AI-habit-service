package com.booster.social.service;

import com.booster.participant.repository.ChallengeParticipantRepository;
import com.booster.shared.common.UnauthorizedException;
import com.booster.social.domain.ChatMessage;
import com.booster.social.dto.ChatMessageResponse;
import com.booster.social.repository.ChatMessageRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
@RequiredArgsConstructor
public class TeamChatService {

    private final ChatMessageRepository chatMessageRepository;
    private final ChallengeParticipantRepository participantRepository;

    @Transactional(readOnly = true)
    public Page<ChatMessageResponse> getMessages(Long teamId, Pageable pageable) {
        return chatMessageRepository
                .findByTeamIdAndDeletedAtIsNullOrderByCreatedAtDesc(teamId, pageable)
                .map(ChatMessageResponse::from);
    }

    public ChatMessageResponse sendMessage(Long senderId, Long teamId, String content) {
        boolean isMember = participantRepository.findByTeamId(teamId).stream()
                .anyMatch(p -> p.getUserId().equals(senderId));

        if (!isMember) {
            throw new UnauthorizedException("User " + senderId + " is not a member of team " + teamId);
        }

        ChatMessage message = ChatMessage.builder()
                .teamId(teamId)
                .senderId(senderId)
                .content(content)
                .build();

        return ChatMessageResponse.from(chatMessageRepository.save(message));
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
    }
}
