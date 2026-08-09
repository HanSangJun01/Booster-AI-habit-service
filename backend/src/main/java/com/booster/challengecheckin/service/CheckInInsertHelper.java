package com.booster.challengecheckin.service;

import com.booster.challengecheckin.domain.ChallengeCheckIn;
import com.booster.challengecheckin.repository.ChallengeCheckInRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Component
@RequiredArgsConstructor
public class CheckInInsertHelper {

    private final ChallengeCheckInRepository checkInRepository;

    /**
     * (BS-39 I1) 체크인 레코드를 독립 트랜잭션(REQUIRES_NEW)에서 삽입한다.
     *
     * <p>이전 구현은 여기서 {@code DataIntegrityViolationException}을 잡아 곧바로
     * {@code findBy...}로 재조회했는데, 그 catch가 REQUIRES_NEW 경계 <b>안</b>에서 일어나
     * 이미 오염된(실패 엔티티가 id=null로 남은) 영속성 컨텍스트를 그대로 재사용했다.
     * 그 상태에서 조회가 flush를 유발해 {@code AssertionFailure: null id ...} → 500이 났다
     * (같은 유저 동시 첫 체크인 시 재현. A축 C4와 같은 계열 버그).
     *
     * <p>수정: 여기서는 <b>삽입만</b> 하고 제약위반은 <b>밖으로 전파</b>시킨다. REQUIRES_NEW
     * 트랜잭션이 깨끗하게 롤백되며, 폴백 재조회는 호출자의 (오염되지 않은) 트랜잭션에서 한다.
     * {@code saveAndFlush}로 위반을 이 호출 시점에 확정적으로 표면화한다.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public ChallengeCheckIn insertInNewTransaction(ChallengeCheckIn newCheckIn) {
        return checkInRepository.saveAndFlush(newCheckIn);
    }
}
