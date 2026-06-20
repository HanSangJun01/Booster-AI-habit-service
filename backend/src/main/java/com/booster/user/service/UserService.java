package com.booster.user.service;

import com.booster.coin.repository.CoinTransactionRepository;
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

    @Transactional(readOnly = true)
    public MyPageResponse getMyPage(Long userId) {
        return MyPageResponse.from(getActiveUser(userId));
    }

    @Transactional(readOnly = true)
    public CoinHistoryResponse getCoinHistory(Long userId, Pageable pageable) {
        Page<CoinTransactionResponse> page = coinTransactionRepository
                .findByUserIdOrderByCreatedAtDesc(userId, pageable)
                .map(CoinTransactionResponse::from);
        return new CoinHistoryResponse(page.getContent(), page.getTotalElements());
    }

    /** 회원 탈퇴(soft delete). B축 챌린지 연동(activeUntil 마킹)은 통합 Phase에서 처리. */
    @Transactional
    public void withdraw(Long userId) {
        getActiveUser(userId).deactivate();
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
