package com.booster.challengecheckin.service;

import org.springframework.http.HttpStatus;

/**
 * AI 인증 파이프라인 예외. status 기반으로 GlobalExceptionHandler에서 응답 매핑.
 * - BAD_REQUEST / PAYLOAD_TOO_LARGE / UNSUPPORTED_MEDIA_TYPE: 이미지 검증 실패
 * - BAD_GATEWAY: ai-service upstream 5xx / timeout / IO 실패
 * - INTERNAL_SERVER_ERROR: 그 외 내부 조립·직렬화 실패
 */
public class AiVerificationException extends RuntimeException {

    private final HttpStatus status;

    public AiVerificationException(HttpStatus status, String message) {
        super(message);
        this.status = status;
    }

    public AiVerificationException(HttpStatus status, String message, Throwable cause) {
        super(message, cause);
        this.status = status;
    }

    public AiVerificationException(String message) {
        this(HttpStatus.INTERNAL_SERVER_ERROR, message);
    }

    public AiVerificationException(String message, Throwable cause) {
        this(HttpStatus.INTERNAL_SERVER_ERROR, message, cause);
    }

    public HttpStatus getStatus() {
        return status;
    }
}
