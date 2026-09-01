package com.booster.user.repository;

import com.booster.user.domain.User;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    /**
     * 활성 계정 중 같은 닉네임이 있는가.
     *
     * <p>탈퇴한 계정의 닉네임까지 막으면 쓸 수 있는 이름이 계속 줄어들기만 하므로 active 만 본다.
     * DB 유니크 제약은 두지 않는다 — 기존 데이터에 이미 중복이 있고, 닉네임은 이메일과 달리
     * 계정 식별자가 아니다.
     */
    boolean existsByNicknameAndActiveTrue(String nickname);

    boolean existsByIdAndActiveTrue(Long id);

    List<User> findAllByActiveTrue();

    /** 코인 잔액 갱신 시 동시성 보호용 비관적 락 조회. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from User u where u.id = :id")
    Optional<User> findByIdForUpdate(@Param("id") Long id);
}
