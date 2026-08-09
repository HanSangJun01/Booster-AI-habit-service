package com.booster.social.repository;

import com.booster.social.domain.ChatMessage;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, Long> {

    Page<ChatMessage> findByTeamIdAndDeletedAtIsNullOrderByCreatedAtDesc(Long teamId, Pageable pageable);
}
