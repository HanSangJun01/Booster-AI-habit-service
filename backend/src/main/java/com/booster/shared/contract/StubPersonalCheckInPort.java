package com.booster.shared.contract;

import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

@Slf4j
@Component
@Profile("stub")
public class StubPersonalCheckInPort implements PersonalCheckInPort {

    @Override
    public void recordPersonalCheckIn(Long userId, LocalDate date, double currentLat, double currentLng) {
        log.info("[STUB] personalCheckIn userId={} date={}", userId, date);
    }
}
