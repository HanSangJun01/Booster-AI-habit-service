package com.booster.participant.controller;

import com.booster.participant.service.ParticipationService;
import com.booster.shared.common.GlobalExceptionHandler;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(ParticipantController.class)
@Import(GlobalExceptionHandler.class)
class ParticipantControllerTest {

    @Autowired
    MockMvc mockMvc;

    @MockBean
    ParticipationService participationService;

    @Test
    void cancel_whenTargetUserIdDiffersFromCallerUserId_shouldReturn403() throws Exception {
        Long callerId = 1L;
        Long targetId = 99L;

        mockMvc.perform(delete("/api/challenges/1/participants/{targetUserId}", targetId)
                        .header("X-User-Id", callerId))
                .andExpect(status().isForbidden());
    }

    @Test
    void cancel_whenTargetUserIdMatchesCaller_shouldSucceed() throws Exception {
        Long userId = 1L;

        mockMvc.perform(delete("/api/challenges/1/participants/{targetUserId}", userId)
                        .header("X-User-Id", userId))
                .andExpect(status().isOk());

        verify(participationService).cancelParticipation(userId, 1L);
    }
}
