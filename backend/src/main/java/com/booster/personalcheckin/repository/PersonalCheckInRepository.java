package com.booster.personalcheckin.repository;

import com.booster.personalcheckin.domain.PersonalCheckIn;
import com.booster.personalcheckin.domain.PersonalCheckInStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface PersonalCheckInRepository extends JpaRepository<PersonalCheckIn, Long> {

    Optional<PersonalCheckIn> findByUserIdAndDate(Long userId, LocalDate date);

    boolean existsByUserIdAndDate(Long userId, LocalDate date);

    List<PersonalCheckIn> findByUserIdAndDateBetween(Long userId, LocalDate start, LocalDate end);

    long countByUserIdAndStatusAndDateBetween(
            Long userId, PersonalCheckInStatus status, LocalDate start, LocalDate end);

    /** 스케줄러: 특정 날짜에 체크인 레코드가 있는 user_id 목록(미인증자 판별용). */
    @org.springframework.data.jpa.repository.Query(
            "select c.userId from PersonalCheckIn c where c.date = :date")
    List<Long> findUserIdsWithRecordOnDate(@org.springframework.data.repository.query.Param("date") LocalDate date);
}
