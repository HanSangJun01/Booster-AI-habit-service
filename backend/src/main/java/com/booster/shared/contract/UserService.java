package com.booster.shared.contract;

public interface UserService {

    boolean existsById(Long userId);

    boolean isActive(Long userId);
}
