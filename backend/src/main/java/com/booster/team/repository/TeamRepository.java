package com.booster.team.repository;

import com.booster.team.domain.Team;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface TeamRepository extends JpaRepository<Team, Long> {

    List<Team> findByChallengeId(Long challengeId);

    boolean existsByChallengeId(Long challengeId);
}
