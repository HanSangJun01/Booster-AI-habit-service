package com.booster.social.repository;

import com.booster.social.domain.CheerEmoji;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface CheerEmojiRepository extends JpaRepository<CheerEmoji, Long> {

    List<CheerEmoji> findByChallengeId(Long challengeId);
}
