package com.booster.challengecheckin.service;

import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;

@Component
@RequiredArgsConstructor
public class CheckInInsertHelper {

    private final ChallengeCheckInRepository checkInRepository;

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public ChallengeCheckIn insertOrFetch(ChallengeCheckIn newCheckIn, Long participantId, LocalDate date) {
        try {
            return checkInRepository.save(newCheckIn);
        } catch (DataIntegrityViolationException e) {
            // REQUIRES_NEW 트랜잭션 안에서 rollback됨 — 바깥 트랜잭션은 오염되지 않음
            return checkInRepository.findByParticipantIdAndCheckInDate(participantId, date)
                    .orElseThrow(() -> new IllegalStateException("Check-in conflict unresolvable"));
        }
    }
}
