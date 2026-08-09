package com.booster.participant.controller;

import com.booster.participant.service.ParticipationService;
import com.booster.shared.common.GlobalExceptionHandler;
import com.booster.shared.security.JwtAuthenticationFilter;
import com.booster.shared.security.JwtTokenProvider;
import com.booster.user.repository.UserRepository;
import com.booster.shared.security.RestAuthenticationEntryPoint;
import com.booster.shared.security.SecurityConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.Mockito.verify;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(ParticipantController.class)
@Import({GlobalExceptionHandler.class, SecurityConfig.class,
        JwtAuthenticationFilter.class, RestAuthenticationEntryPoint.class})
class ParticipantControllerTest {

    @Autowired
    MockMvc mockMvc;

    @MockBean
    ParticipationService participationService;

    @MockBean
    JwtTokenProvider jwtTokenProvider;

    // (BS-39 I16) JwtAuthenticationFilter가 활성상태 검증을 위해 UserRepository를 주입받으므로
    // WebMvcTest 슬라이스에도 목 빈이 필요하다(테스트는 authentication()으로 principal을 직접 주입해
    // 필터의 토큰 경로를 타지 않으므로 스텁 동작은 불필요).
    @MockBean
    UserRepository userRepository;

    /** principal = userId(Long) — JwtAuthenticationFilter가 세팅하는 형태와 동일. */
    private static UsernamePasswordAuthenticationToken authUser(Long userId) {
        return new UsernamePasswordAuthenticationToken(userId, null, List.of());
    }

    @Test
    void cancel_whenTargetUserIdDiffersFromCallerUserId_shouldReturn403() throws Exception {
        Long callerId = 1L;
        Long targetId = 99L;

        mockMvc.perform(delete("/api/challenges/1/participants/{targetUserId}", targetId)
                        .with(authentication(authUser(callerId))))
                .andExpect(status().isForbidden());
    }

    @Test
    void cancel_whenTargetUserIdMatchesCaller_shouldSucceed() throws Exception {
        Long userId = 1L;

        mockMvc.perform(delete("/api/challenges/1/participants/{targetUserId}", userId)
                        .with(authentication(authUser(userId))))
                .andExpect(status().isOk());

        verify(participationService).cancelParticipation(userId, 1L);
    }
}
