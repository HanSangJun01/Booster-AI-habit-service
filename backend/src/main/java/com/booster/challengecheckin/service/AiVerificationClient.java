package com.booster.challengecheckin.service;

import com.booster.challengecheckin.dto.AiServiceVerdict;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.UUID;

@Slf4j
@Component
@RequiredArgsConstructor
public class AiVerificationClient {

    @Value("${AI_SERVICE_URL:http://localhost:8000}")
    private String baseUrl;

    private final ObjectMapper objectMapper;
    private HttpClient httpClient;

    @PostConstruct
    void init() {
        this.httpClient = HttpClient.newBuilder()
                .version(HttpClient.Version.HTTP_1_1)
                .connectTimeout(Duration.ofSeconds(5))
                .build();
    }

    public AiServiceVerdict verify(String category, byte[] imageBytes, String filename, MediaType mediaType) {
        String boundary = "----BoosterBoundary" + UUID.randomUUID();
        byte[] body = buildMultipartBody(boundary, category, imageBytes, filename, mediaType.toString());

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(baseUrl + "/verify"))
                .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .timeout(Duration.ofSeconds(30))
                .POST(HttpRequest.BodyPublishers.ofByteArray(body))
                .build();

        try {
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            int status = response.statusCode();
            if (status / 100 == 2) {
                return objectMapper.readValue(response.body(), AiServiceVerdict.class);
            }
            // upstream 5xx는 게이트웨이 실패로 취급(502). 4xx는 클라이언트 계약 오류이므로 500(내부 버그).
            if (status / 100 == 5) {
                log.error("ai-service upstream {}: {}", status, response.body());
                throw new AiVerificationException(HttpStatus.BAD_GATEWAY,
                        "AI 판정 서비스 오류 (" + status + ")");
            }
            log.error("ai-service unexpected {}: {}", status, response.body());
            throw new AiVerificationException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "AI 판정 계약 오류 (" + status + "): " + response.body());
        } catch (HttpTimeoutException e) {
            log.error("ai-service timeout: category={}, filename={}", category, filename, e);
            throw new AiVerificationException(HttpStatus.BAD_GATEWAY,
                    "AI 판정 서비스 타임아웃", e);
        } catch (IOException e) {
            log.error("ai-service IO failure: category={}, filename={}", category, filename, e);
            throw new AiVerificationException(HttpStatus.BAD_GATEWAY,
                    "AI 판정 서비스 통신 실패: " + e.getMessage(), e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new AiVerificationException(HttpStatus.BAD_GATEWAY,
                    "AI 판정 서비스 호출 중단", e);
        }
    }

    private byte[] buildMultipartBody(String boundary, String category, byte[] imageBytes,
                                      String filename, String contentType) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            out.write(("--" + boundary + "\r\n").getBytes(StandardCharsets.UTF_8));
            out.write("Content-Disposition: form-data; name=\"category\"\r\n\r\n".getBytes(StandardCharsets.UTF_8));
            out.write(category.getBytes(StandardCharsets.UTF_8));
            out.write("\r\n".getBytes(StandardCharsets.UTF_8));

            out.write(("--" + boundary + "\r\n").getBytes(StandardCharsets.UTF_8));
            out.write(("Content-Disposition: form-data; name=\"image\"; filename=\"" + filename + "\"\r\n")
                    .getBytes(StandardCharsets.UTF_8));
            out.write(("Content-Type: " + contentType + "\r\n\r\n").getBytes(StandardCharsets.UTF_8));
            out.write(imageBytes);
            out.write("\r\n".getBytes(StandardCharsets.UTF_8));

            out.write(("--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new AiVerificationException("multipart body 조립 실패", e);
        }
        return out.toByteArray();
    }
}
