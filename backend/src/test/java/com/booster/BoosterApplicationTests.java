package com.booster;

import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

import static org.junit.jupiter.api.Assertions.assertNotNull;

// DB 없이 컴파일 및 어노테이션 존재 여부만 검증
// 실제 컨텍스트 통합 테스트는 DB 연동 시 추가
class BoosterApplicationTests {

    @Test
    void applicationClassHasSpringBootApplicationAnnotation() {
        assertNotNull(BoosterApplication.class.getAnnotation(SpringBootApplication.class));
    }

    @Test
    void applicationClassHasEnableSchedulingAnnotation() {
        assertNotNull(BoosterApplication.class.getAnnotation(EnableScheduling.class));
    }
}
