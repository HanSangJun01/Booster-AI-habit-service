package com.booster.user.service;

import com.booster.coin.repository.CoinTransactionRepository;
import com.booster.participant.service.ParticipationService;
import com.booster.shared.common.BusinessException;
import com.booster.user.domain.User;
import com.booster.user.dto.CoinHistoryResponse;
import com.booster.user.dto.CoinTransactionResponse;
import com.booster.user.dto.MyPageResponse;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final CoinTransactionRepository coinTransactionRepository;
    private final ParticipationService participationService;

    @Transactional(readOnly = true)
    public MyPageResponse getMyPage(Long userId) {
        return MyPageResponse.from(getActiveUser(userId));
    }

    @Transactional(readOnly = true)
    public CoinHistoryResponse getCoinHistory(Long userId, Pageable pageable) {
        getActiveUser(userId); // (BS-30 F11) 탈퇴(비활성) 계정 차단 — 마이페이지와 동일 가드
        Page<CoinTransactionResponse> page = coinTransactionRepository
                .findByUserIdOrderByCreatedAtDescIdDesc(userId, pageable)
                .map(CoinTransactionResponse::from);
        return new CoinHistoryResponse(page.getContent(), page.getTotalElements());
    }

    /**
     * 회원 탈퇴(soft delete). (BS-39 I15) 탈퇴 전에 시작 전(READY) 챌린지 참여를 환불·정리한다.
     * 예전엔 deactivate만 해서 탈퇴 후에도 참여·예치금이 남아 정산에 좀비로 집계됐다.
     */
    @Transactional
    public void withdraw(Long userId) {
        // (BS-30 7차 C#5) 비관락으로 로드 → 인증/복귀의 락 기반 active 재확인과 직렬화(무락 write 제거).
        User user = userRepository.findByIdForUpdate(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        if (!user.isActive()) {
            throw BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다.");
        }
        // (BS-39 I15) 진행 전 챌린지의 참여 정리·예치금 환불. deactivate 이후엔 좀비 참여가 남으므로 먼저 수행.
        participationService.cancelActiveParticipationsForWithdrawal(userId);
        user.deactivate();
    }

    private User getActiveUser(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다."));
        if (!user.isActive()) {
            throw BusinessException.notFound("USER_NOT_FOUND", "사용자를 찾을 수 없습니다.");
        }
        return user;
    }
}
