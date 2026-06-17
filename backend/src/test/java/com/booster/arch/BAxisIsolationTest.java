package com.booster.arch;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.fail;

/**
 * 흐름 분리 불변식 (BS-19 Principle 1)
 * B-axis 모듈은 PersonalCheckIn / RecoveryMission / Streak 에 쓰기 의존성을 갖지 않는다.
 */
class BAxisIsolationTest {

    private static final Path B_AXIS_ROOT = Paths.get("src/main/java/com/booster");

    private static final List<String> B_AXIS_PACKAGES = List.of(
            "challengecheckin",
            "settlement"
    );

    private static final List<String> FORBIDDEN_SYMBOLS = List.of(
            "PersonalCheckIn",
            "RecoveryMission",
            "Streak"
    );

    @Test
    void bAxisShouldNotDependOnPersonalCheckInOrStreakOrRecoveryMission() throws IOException {
        StringBuilder violations = new StringBuilder();

        for (String pkg : B_AXIS_PACKAGES) {
            Path pkgPath = B_AXIS_ROOT.resolve(pkg);
            if (!Files.exists(pkgPath)) continue;

            try (Stream<Path> walk = Files.walk(pkgPath)) {
                walk.filter(p -> p.toString().endsWith(".java"))
                        .forEach(file -> {
                            try {
                                String content = Files.readString(file);
                                for (String symbol : FORBIDDEN_SYMBOLS) {
                                    if (content.contains(symbol)) {
                                        violations.append("\n  ").append(file)
                                                .append(" references '").append(symbol).append("'");
                                    }
                                }
                            } catch (IOException e) {
                                throw new RuntimeException(e);
                            }
                        });
            }
        }

        if (!violations.isEmpty()) {
            fail("B-axis isolation violation — 흐름 분리 불변식 위반:" + violations);
        }
    }
}
