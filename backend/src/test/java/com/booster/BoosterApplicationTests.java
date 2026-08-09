package com.booster;

import com.booster.support.TestClockConfig;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
@Import(TestClockConfig.class)
class BoosterApplicationTests {

    @Test
    void contextLoads() {
    }
}
