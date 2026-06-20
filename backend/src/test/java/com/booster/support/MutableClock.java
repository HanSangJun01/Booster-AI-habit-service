package com.booster.support;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;

/** 테스트용 가변 시계. 날짜/시각을 임의로 이동시켜 스트릭·데드라인 로직을 검증한다. */
public class MutableClock extends Clock {

    public static final ZoneId KST = ZoneId.of("Asia/Seoul");

    private Instant instant;
    private final ZoneId zone;

    public MutableClock(Instant instant, ZoneId zone) {
        this.instant = instant;
        this.zone = zone;
    }

    public static MutableClock at(LocalDate date) {
        MutableClock c = new MutableClock(Instant.EPOCH, KST);
        c.setDate(date);
        return c;
    }

    /** 해당 날짜 12:00 KST로 설정. */
    public void setDate(LocalDate date) {
        this.instant = date.atTime(LocalTime.NOON).atZone(zone).toInstant();
    }

    public void setDateTime(LocalDate date, LocalTime time) {
        this.instant = date.atTime(time).atZone(zone).toInstant();
    }

    public void advanceDays(long days) {
        this.instant = this.instant.plus(java.time.Duration.ofDays(days));
    }

    @Override
    public ZoneId getZone() {
        return zone;
    }

    @Override
    public Clock withZone(ZoneId zone) {
        return new MutableClock(instant, zone);
    }

    @Override
    public Instant instant() {
        return instant;
    }
}
