package com.booster.shared.contract;

import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@Profile("stub")
public class StubUserService implements UserService {

    @Override
    public boolean existsById(Long userId) {
        return true;
    }

    @Override
    public boolean isActive(Long userId) {
        return true;
    }
}
