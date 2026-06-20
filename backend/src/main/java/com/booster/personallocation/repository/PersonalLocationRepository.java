package com.booster.personallocation.repository;

import com.booster.personallocation.domain.PersonalLocation;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PersonalLocationRepository extends JpaRepository<PersonalLocation, Long> {
}
