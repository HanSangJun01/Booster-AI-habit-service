package com.booster.team.service;

import com.booster.participant.domain.ChallengeParticipant;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [멀티서버 확장 P2] {@link TeamFormationService#orderForAssignment} 의 <em>입력순서 독립적</em> 결정성.
 *
 * <p>기존 결정성 검증(C8)은 같은 challengeId 로 두 번 팀을 구성해 결과가 같은지만 봤다. 하지만
 * 그 경로에서는 {@code findByChallengeIdAndStatus} 가 (같은 DB에서는) 대체로 같은 순서로 row 를
 * 돌려주므로, "입력 순서가 달라졌을 때도" 결과가 같은지는 검증하지 못했다. 실제 멀티서버에서는
 * ORDER BY 부재로 인스턴스마다 입력 순서가 다를 수 있다.
 *
 * <p>이 테스트는 DB 없이, 같은 참여자 집합을 <em>서로 다른 순서</em>로 넣어도
 * {@code orderForAssignment} 결과가 동일함을 검증한다. id 안정정렬이 빠지면(옛 구현) 셔플 입력
 * 순서가 달라 결과가 달라지므로 RED 가 되고, 안정정렬이 있으면 GREEN 이 된다.
 */
class TeamFormationOrderingTest {

    @Test
    @DisplayName("입력 순서가 달라도 orderForAssignment 결과(참여자 id 순서)는 동일해야 한다")
    void orderForAssignment_isIndependentOfInputOrder() {
        List<ChallengeParticipant> base = participants(10L, 20L, 30L, 40L, 50L,
                60L, 70L, 80L, 90L, 100L);

        // 같은 참여자 집합의 서로 다른 입력 순서 (셔플로 재배열).
        List<ChallengeParticipant> reordered = new ArrayList<>(base);
        Collections.shuffle(reordered, new Random(9999)); // base 와 확실히 다른 순서

        List<Long> fromBase = ids(TeamFormationService.orderForAssignment(base, 42L));
        List<Long> fromReordered = ids(TeamFormationService.orderForAssignment(reordered, 42L));

        assertThat(fromReordered)
                .as("입력 순서와 무관하게 동일한 배정 순서가 나와야 크로스 인스턴스 결정성이 성립한다")
                .isEqualTo(fromBase);
    }

    // ---- 헬퍼 ------------------------------------------------------------

    private static List<ChallengeParticipant> participants(Long... ids) {
        List<ChallengeParticipant> list = new ArrayList<>();
        for (Long id : ids) {
            list.add(ChallengeParticipant.builder().id(id).build());
        }
        return list;
    }

    private static List<Long> ids(List<ChallengeParticipant> ps) {
        return ps.stream().map(ChallengeParticipant::getId).toList();
    }
}
