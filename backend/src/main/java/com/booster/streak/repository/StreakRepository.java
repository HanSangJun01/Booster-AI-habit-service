package com.booster.streak.repository;

import com.booster.streak.domain.Streak;
import org.springframework.data.jpa.repository.JpaRepository;

public interface StreakRepository extends JpaRepository<Streak, Long> {
}
