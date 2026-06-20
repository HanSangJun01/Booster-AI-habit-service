package com.booster.auth;

import com.booster.support.TestClockConfig;
import com.booster.user.domain.User;
import com.booster.user.repository.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestClockConfig.class)
class AuthIntegrationTest {

    @Autowired
    MockMvc mockMvc;
    @Autowired
    ObjectMapper objectMapper;
    @Autowired
    UserRepository userRepository;

    private String json(Object o) throws Exception {
        return objectMapper.writeValueAsString(o);
    }

    @Test
    void signup_createsUserWithBonusCoinsAndStreak() throws Exception {
        mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("email", "a@test.com", "password", "password1234", "nickname", "tester"))))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.email").value("a@test.com"))
                .andExpect(jsonPath("$.coinBalance").value(500));

        User user = userRepository.findByEmail("a@test.com").orElseThrow();
        assertThat(user.getCoinBalance()).isEqualTo(500L);
        assertThat(user.isActive()).isTrue();
    }

    @Test
    void signup_duplicateEmail_returns409() throws Exception {
        String body = json(Map.of("email", "dup@test.com", "password", "password1234", "nickname", "dup"));
        mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated());
        mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("DUPLICATE_EMAIL"));
    }

    @Test
    void login_returnsAccessToken() throws Exception {
        mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("email", "login@test.com", "password", "password1234", "nickname", "login"))));

        mockMvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("email", "login@test.com", "password", "password1234"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isNotEmpty());
    }

    @Test
    void login_wrongPassword_returns401() throws Exception {
        mockMvc.perform(post("/api/auth/signup").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("email", "wrong@test.com", "password", "password1234", "nickname", "wrong"))));

        mockMvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("email", "wrong@test.com", "password", "wrongpassword"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("INVALID_CREDENTIALS"));
    }

    @Test
    void protectedEndpoint_withoutToken_returns401() throws Exception {
        mockMvc.perform(post("/api/personal/check-in").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("lat", 37.0, "lng", 127.0))))
                .andExpect(status().isUnauthorized());
    }
}
