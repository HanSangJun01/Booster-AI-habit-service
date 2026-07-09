package com.booster.shared.contract;

import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** B축 {@link UserService} 포트 → A축 users 테이블 조회 어댑터. */
@Component
@RequiredArgsConstructor
public class UserServiceAdapter implements UserService {

    private final UserRepository userRepository;

    @Override
    @Transactional(readOnly = true)
    public boolean existsById(Long userId) {
        return userRepository.existsById(userId);
    }

    @Override
    @Transactional(readOnly = true)
    public boolean isActive(Long userId) {
        return userRepository.findById(userId).map(User::isActive).orElse(false);
    }
}
