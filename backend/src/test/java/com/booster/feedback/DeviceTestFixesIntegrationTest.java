package com.booster.feedback;

import com.booster.personallocation.repository.PersonalLocationRepository;
import com.booster.support.TestClockConfig;
import com.booster.user.repository.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 실기기 테스트에서 나온 결함들의 회귀 테스트.
 *
 * <p>대부분 "값이 검증되지 않는다" 또는 "한 번 하고 나면 되돌릴 수 없다" 계열이라, 서비스 단위가
 * 아니라 요청부터 응답까지 태워야 재현된다. 그래서 MockMvc 통합 테스트로 둔다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestClockConfig.class)
class DeviceTestFixesIntegrationTest {

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;
    @Autowired UserRepository userRepository;
    @Autowired PersonalLocationRepository personalLocationRepository;

    private static final AtomicInteger SEQ = new AtomicInteger();
    private static final double LAT = 37.5;
    private static final double LNG = 127.0;

    private String json(Object o) throws Exception {
        return objectMapper.writeValueAsString(o);
    }

    /** principal = userId(Long) — JwtAuthenticationFilter 가 세팅하는 형태와 동일. */
    private static UsernamePasswordAuthenticationToken auth(Long userId) {
        return new UsernamePasswordAuthenticationToken(userId, null, List.of());
    }

    private long signup(String tag) throws Exception {
        int n = SEQ.incrementAndGet();
        String body = mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "email", tag + n + "-" + System.nanoTime() + "@dev.test",
                                "password", "password1234",
                                "nickname", tag + n + "-" + System.nanoTime()))))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(body).get("userId").asLong();
    }

    private void registerLocation(long userId, int radius) throws Exception {
        mockMvc.perform(post("/api/users/me/location").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("lat", LAT, "lng", LNG,
                                "radiusMeters", radius, "placeName", "home"))))
                .andExpect(status().isCreated());
    }

    /** 기본 챌린지 요청 본문. 개별 테스트가 필요한 값만 덮어쓴다. */
    private Map<String, Object> challengeBody() {
        Map<String, Object> m = new HashMap<>();
        m.put("category", "EXERCISE");
        m.put("verificationType", "GPS_PHOTO_AI");
        m.put("durationDays", 7);
        m.put("depositCoins", 100);
        m.put("visibility", "PUBLIC");
        m.put("approvalType", "AUTO");
        m.put("maxParticipants", 10);
        m.put("gpsLat", LAT);
        m.put("gpsLng", LNG);
        m.put("gpsRadiusMeters", 300);
        return m;
    }

    private long createChallenge(long userId, Map<String, Object> body) throws Exception {
        String res = mockMvc.perform(post("/api/challenges").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(body)))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(res).get("data").get("id").asLong();
    }

    private Map<String, Object> joinBody() {
        Map<String, Object> m = new HashMap<>();
        m.put("gpsLat", LAT);
        m.put("gpsLng", LNG);
        m.put("gpsRadiusMeters", 300);
        m.put("gpsPlaceName", "park");
        return m;
    }

    // ────────────────────────── 검증 상·하한 ──────────────────────────

    @Test
    @DisplayName("반경 상한: 2,000만m 등록은 400 — 서울에 등록하고 시드니에서 인증되던 구멍")
    void locationRadiusUpperBoundIsEnforced() throws Exception {
        long userId = signup("radius");
        mockMvc.perform(post("/api/users/me/location").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("lat", LAT, "lng", LNG,
                                "radiusMeters", 20_000_000, "placeName", "earth"))))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("반경 하한: 1m 는 400 — GPS 오차보다 좁으면 제자리에서도 인증이 실패한다")
    void locationRadiusLowerBoundIsEnforced() throws Exception {
        long userId = signup("radiusmin");
        mockMvc.perform(post("/api/users/me/location").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("lat", LAT, "lng", LNG,
                                "radiusMeters", 1, "placeName", "pin"))))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("예치금 하한: 100코인 미만 챌린지는 400")
    void challengeDepositHasMinimum() throws Exception {
        long userId = signup("deposit");
        registerLocation(userId, 300);
        Map<String, Object> body = challengeBody();
        body.put("depositCoins", 10);
        mockMvc.perform(post("/api/challenges").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(body)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("카테고리: 운동·공부 외의 값은 400")
    void challengeCategoryIsRestricted() throws Exception {
        long userId = signup("cat");
        registerLocation(userId, 300);
        Map<String, Object> body = challengeBody();
        body.put("category", "WAKE_UP");
        mockMvc.perform(post("/api/challenges").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(body)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("인증 방식: 위치+사진 외의 값은 400")
    void challengeVerificationTypeIsFixed() throws Exception {
        long userId = signup("vtype");
        registerLocation(userId, 300);
        Map<String, Object> body = challengeBody();
        body.put("verificationType", "GPS");
        mockMvc.perform(post("/api/challenges").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(body)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("기간 상한: 366일은 400 — 20억일 방이 정원 채워지는 순간 팀 편성을 깨뜨렸다")
    void challengeDurationHasMaximum() throws Exception {
        long userId = signup("durmax");
        registerLocation(userId, 300);
        Map<String, Object> body = challengeBody();
        body.put("durationDays", 366);
        mockMvc.perform(post("/api/challenges").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(body)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("기간 상한: int 최대값에 가까운 값도 막힌다 — 종료일이 timestamptz 범위를 넘던 경로")
    void challengeDurationRejectsAbsurdValue() throws Exception {
        long userId = signup("durhuge");
        registerLocation(userId, 300);
        Map<String, Object> body = challengeBody();
        body.put("durationDays", 2_000_000_000);
        mockMvc.perform(post("/api/challenges").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(body)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("기간 경계: 365일까지는 통과 — 앱이 쓰는 7·14·21·30 을 막지 않는다")
    void challengeDurationAllowsBoundary() throws Exception {
        long userId = signup("durok");
        registerLocation(userId, 300);
        Map<String, Object> body = challengeBody();
        body.put("durationDays", 365);
        createChallenge(userId, body);
    }

    @Test
    @DisplayName("설명 상한: 1,000자를 넘으면 400 — 목록 응답에 항목마다 실려 나가는 값이다")
    void challengeDescriptionHasMaximum() throws Exception {
        long userId = signup("descmax");
        registerLocation(userId, 300);
        Map<String, Object> body = challengeBody();
        body.put("description", "가".repeat(1001));
        mockMvc.perform(post("/api/challenges").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(body)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("설명 경계: 1,000자까지는 통과")
    void challengeDescriptionAllowsBoundary() throws Exception {
        long userId = signup("descok");
        registerLocation(userId, 300);
        Map<String, Object> body = challengeBody();
        body.put("description", "가".repeat(1000));
        createChallenge(userId, body);
    }

    @Test
    @DisplayName("응원 이모지: 50자를 넘으면 400 — DB VARCHAR(50)에서 터져 409 \"충돌\"로 잘못 나가던 값")
    void cheerEmojiTypeHasMaximum() throws Exception {
        long userId = signup("emoji");
        registerLocation(userId, 300);
        long challengeId = createChallenge(userId, challengeBody());
        // 서비스도 400(SELF_CHEER 등)을 던지므로 상태 코드만으로는 구분되지 않는다 → 코드까지 본다.
        mockMvc.perform(post("/api/challenges/{id}/cheers", challengeId).with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("toParticipantId", 1, "emojiType", "F".repeat(51)))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errorCode").value("VALIDATION_ERROR"));
    }

    // ────────────────────────── 계정 ──────────────────────────

    @Test
    @DisplayName("닉네임 중복: 같은 닉네임으로는 가입할 수 없다")
    void duplicateNicknameIsRejected() throws Exception {
        String nickname = "dupnick" + System.nanoTime();
        mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("email", "n1-" + System.nanoTime() + "@dev.test",
                                "password", "password1234", "nickname", nickname))))
                .andExpect(status().isCreated());

        mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("email", "n2-" + System.nanoTime() + "@dev.test",
                                "password", "password1234", "nickname", nickname))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.errorCode").value("DUPLICATE_NICKNAME"));
    }

    @Test
    @DisplayName("탈퇴 후 같은 이메일로 다시 가입할 수 있다")
    void withdrawnEmailCanSignupAgain() throws Exception {
        String email = "again-" + System.nanoTime() + "@dev.test";
        String first = mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("email", email, "password", "password1234",
                                "nickname", "again1-" + System.nanoTime()))))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        long userId = objectMapper.readTree(first).get("userId").asLong();

        mockMvc.perform(delete("/api/users/me").with(authentication(auth(userId))))
                .andExpect(status().isNoContent());

        // 예전에는 탈퇴 계정이 이메일을 쥐고 있어 "이미 사용 중인 이메일" 로 막혔다.
        mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("email", email, "password", "password1234",
                                "nickname", "again2-" + System.nanoTime()))))
                .andExpect(status().isCreated());
    }

    // ────────────────────────── 참가 ──────────────────────────

    @Test
    @DisplayName("참가 응답이 코인 잔액을 담는다 — 없으면 앱이 재로그인해야 차감이 보였다")
    void joinResponseCarriesCoinBalance() throws Exception {
        long leader = signup("owner");
        registerLocation(leader, 300);
        long challengeId = createChallenge(leader, challengeBody());

        long member = signup("member");
        mockMvc.perform(post("/api/challenges/{id}/participants", challengeId)
                        .with(authentication(auth(member)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(joinBody())))
                .andExpect(status().isCreated())
                // 가입 보너스 500 - 예치금 100
                .andExpect(jsonPath("$.data.coinBalance").value(400));
    }

    @Test
    @DisplayName("취소했다가 다시 참가할 수 있다 — 예전엔 취소 행 때문에 영영 막혔다")
    void cancelledParticipantCanRejoin() throws Exception {
        long leader = signup("rjowner");
        registerLocation(leader, 300);
        long challengeId = createChallenge(leader, challengeBody());

        long member = signup("rjmember");
        mockMvc.perform(post("/api/challenges/{id}/participants", challengeId)
                        .with(authentication(auth(member)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(joinBody())))
                .andExpect(status().isCreated());

        mockMvc.perform(delete("/api/challenges/{id}/participants/{userId}", challengeId, member)
                        .with(authentication(auth(member))))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/challenges/{id}/participants", challengeId)
                        .with(authentication(auth(member)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(joinBody())))
                .andExpect(status().isCreated());
    }

    // ────────────────────────── 방 해산 ──────────────────────────

    @Test
    @DisplayName("방장이 방을 취소하면 참가자 예치금이 돌아오고 방이 닫힌다")
    void creatorCanCancelChallengeAndEveryoneIsRefunded() throws Exception {
        long leader = signup("cancelowner");
        registerLocation(leader, 300);
        long challengeId = createChallenge(leader, challengeBody());

        long member = signup("cancelmember");
        mockMvc.perform(post("/api/challenges/{id}/participants", challengeId)
                        .with(authentication(auth(member)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(joinBody())))
                .andExpect(status().isCreated());
        assertThat(userRepository.findById(member).orElseThrow().getCoinBalance()).isEqualTo(400);

        mockMvc.perform(delete("/api/challenges/{id}", challengeId)
                        .with(authentication(auth(leader))))
                .andExpect(status().isOk());

        assertThat(userRepository.findById(member).orElseThrow().getCoinBalance())
                .as("해산하면 예치금이 돌아와야 한다")
                .isEqualTo(500);
    }

    @Test
    @DisplayName("남의 방은 취소할 수 없다")
    void nonCreatorCannotCancelChallenge() throws Exception {
        long leader = signup("guardowner");
        registerLocation(leader, 300);
        long challengeId = createChallenge(leader, challengeBody());

        long stranger = signup("stranger");
        // 로그인은 했으나 권한이 없는 경우라 403 이다(401 은 인증 자체가 없을 때).
        mockMvc.perform(delete("/api/challenges/{id}", challengeId)
                        .with(authentication(auth(stranger))))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("방장이 탈퇴하면 모집 중인 자기 방이 해산되고 참가자가 환불받는다")
    void creatorWithdrawalDisbandsReadyChallenge() throws Exception {
        long leader = signup("wdowner");
        registerLocation(leader, 300);
        long challengeId = createChallenge(leader, challengeBody());

        long member = signup("wdmember");
        mockMvc.perform(post("/api/challenges/{id}/participants", challengeId)
                        .with(authentication(auth(member)))
                        .contentType(MediaType.APPLICATION_JSON).content(json(joinBody())))
                .andExpect(status().isCreated());

        mockMvc.perform(delete("/api/users/me").with(authentication(auth(leader))))
                .andExpect(status().isNoContent());

        assertThat(userRepository.findById(member).orElseThrow().getCoinBalance())
                .as("방장 탈퇴로 방이 해산되면 참가자 예치금이 돌아와야 한다")
                .isEqualTo(500);
    }

    // ────────────────────────── 위치 변경 예약 ──────────────────────────

    @Test
    @DisplayName("위치 변경은 즉시 반영되지 않고 예약된다 — 인증 직전에 자리를 옮기지 못하게")
    void locationChangeIsReservedNotApplied() throws Exception {
        long userId = signup("resv");
        registerLocation(userId, 100);

        mockMvc.perform(put("/api/users/me/location").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("lat", 38.5, "lng", 128.0,
                                "radiusMeters", 200, "placeName", "elsewhere"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.lat").value(LAT))              // 지금 기준은 그대로
                .andExpect(jsonPath("$.pendingLat").value(38.5))      // 예약만 잡힌다
                .andExpect(jsonPath("$.pendingRadiusMeters").value(200));

        var saved = personalLocationRepository.findById(userId).orElseThrow();
        assertThat(saved.getLat()).isEqualTo(LAT);
        assertThat(saved.hasPendingLocation()).isTrue();
    }

    @Test
    @DisplayName("예약 값도 반경 상한을 넘으면 400")
    void reservedLocationRespectsRadiusBounds() throws Exception {
        long userId = signup("resvmax");
        registerLocation(userId, 100);

        mockMvc.perform(put("/api/users/me/location").with(authentication(auth(userId)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("lat", LAT, "lng", LNG,
                                "radiusMeters", 5000, "placeName", "toobig"))))
                .andExpect(status().isBadRequest());
    }
}
