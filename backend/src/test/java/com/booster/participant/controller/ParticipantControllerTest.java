package com.booster.participant.controller;

import com.booster.participant.service.ParticipationService;
import com.booster.shared.common.GlobalExceptionHandler;
import com.booster.shared.security.JwtAuthenticationFilter;
import com.booster.shared.security.JwtTokenProvider;
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
