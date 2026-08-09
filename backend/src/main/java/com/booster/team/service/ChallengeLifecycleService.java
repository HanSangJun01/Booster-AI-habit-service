package com.booster.team.service;

import com.booster.challenge.repository.ChallengeRepository;
import com.booster.shared.common.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class ChallengeLifecycleService {

    private final ChallengeRepository challengeRepository;

    @Transactional
    public LocalDateTime startChallenge(Long challengeId) {
        var challenge = challengeRepository.findById(challengeId)
                .orElseThrow(() -> new ResourceNotFoundException("Challenge", challengeId));

        LocalDateTime now = LocalDateTime.now();
        LocalDateTime endedAt = now.plusDays(challenge.getDurationDays());
        challenge.start(now, endedAt);
        log.info("Challenge started: challengeId={}, endedAt={}", challengeId, endedAt);
        return endedAt;
    }
}
