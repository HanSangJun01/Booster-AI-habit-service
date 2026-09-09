package com.booster.shared.common;

import com.booster.challengecheckin.service.AiVerificationException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.resource.NoResourceFoundException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import java.util.stream.Collectors;

/**
 * A/B축 통합 전역 예외 처리기. 모든 에러를 MVP_API_SPEC §2.3 엔벨로프
 * ({@code {success:false, message, errorCode}})로 응답한다.
 *
 * A축은 서비스 레이어에서 {@link BusinessException}(status+code 보유)을 던지고,
 * B축은 도메인별 예외 타입을 던진다 — 둘 다 여기서 단일 규약으로 변환된다.
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    // --- A축: 서비스 레이어 비즈니스 예외 (status/code를 예외가 직접 보유) ---
    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ApiResponse<Void>> handleBusiness(BusinessException ex) {
        return ResponseEntity.status(ex.getStatus())
                .body(ApiResponse.error(ex.getMessage(), ex.getCode()));
    }

    // --- B축: 도메인별 예외 타입 ---
    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleNotFound(ResourceNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.error(ex.getMessage(), "NOT_FOUND"));
    }

    @ExceptionHandler(UnauthorizedException.class)
    public ResponseEntity<ApiResponse<Void>> handleUnauthorized(UnauthorizedException ex) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(ApiResponse.error(ex.getMessage(), "FORBIDDEN"));
    }

    @ExceptionHandler(InsufficientCoinException.class)
    public ResponseEntity<ApiResponse<Void>> handleInsufficientCoin(InsufficientCoinException ex) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error(ex.getMessage(), "INSUFFICIENT_COIN"));
    }

    @ExceptionHandler(ChallengeFullException.class)
    public ResponseEntity<ApiResponse<Void>> handleChallengeFull(ChallengeFullException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiResponse.error(ex.getMessage(), "CHALLENGE_FULL"));
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<ApiResponse<Void>> handleIllegalState(IllegalStateException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiResponse.error(ex.getMessage(), "ILLEGAL_STATE"));
    }

    /** 잘못된 인자(도메인 검증 실패 등)는 500이 아니라 400으로 응답한다. */
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiResponse<Void>> handleIllegalArgument(IllegalArgumentException ex) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error(ex.getMessage(), "ILLEGAL_ARGUMENT"));
    }

    // --- 공통: 요청/검증/무결성 ---
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleValidation(MethodArgumentNotValidException ex) {
        String message = ex.getBindingResult().getFieldErrors().stream()
                .map(FieldError::getDefaultMessage)
                .collect(Collectors.joining(", "));
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error(message, "VALIDATION_ERROR"));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> handleUnreadable(HttpMessageNotReadableException ex) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error("요청 본문을 해석할 수 없습니다.", "MALFORMED_REQUEST"));
    }

    /** (BS-30 F9) 쿼리 파라미터 타입 불일치(예: page=abc) → 500 대신 400. */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ApiResponse<Void>> handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error("요청 파라미터 형식이 올바르지 않습니다: " + ex.getName(), "INVALID_PARAMETER"));
    }

    /** (BS-39 I11) 필수 요청 파라미터 누락(예: /leaderboards 에 type 없음) → 500 대신 400. */
    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ApiResponse<Void>> handleMissingParam(MissingServletRequestParameterException ex) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error("필수 요청 파라미터가 누락되었습니다: " + ex.getParameterName(), "MISSING_PARAMETER"));
    }

    /**
     * 업로드 용량 초과 → 413.
     *
     * <p>Spring 의 multipart 상한을 넘으면 {@link MaxUploadSizeExceededException} 이 던져지는데,
     * 매핑이 없으면 catch-all 로 떨어져 <b>500 INTERNAL_ERROR</b> 가 된다. 클라이언트는 "사진이
     * 너무 큽니다"를 안내해야 하는데 "서버 오류"로 보여 원인을 알 수 없다.
     * ai-service·AiVerificationService 와 동일하게 413 으로 통일한다.
     */
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ApiResponse<Void>> handleUploadTooLarge(MaxUploadSizeExceededException ex) {
        log.warn("Upload exceeds max size: {}", ex.getMessage());
        return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE)
                .body(ApiResponse.error("업로드 용량이 너무 큽니다. 10MB 이하의 이미지를 사용하세요.",
                        "PAYLOAD_TOO_LARGE"));
    }

    /**
     * 매핑되지 않은 경로 → 404.
     *
     * <p>Spring Boot 3 는 핸들러를 못 찾으면 {@link NoResourceFoundException} 을 던지는데, 이 매핑이
     * 없으면 catch-all {@code Exception} 핸들러로 떨어져 <b>모든 오타 URL 이 500 INTERNAL_ERROR</b>
     * 로 나간다. 실제 영향:
     * <ul>
     *   <li>클라이언트가 "경로 오타"를 "서버 장애"로 오인한다</li>
     *   <li>5xx 기반 모니터링·알람이 오작동한다</li>
     *   <li>폐지된 엔드포인트를 호출해도 500이라 클라이언트가 원인을 알 수 없다</li>
     * </ul>
     */
    @ExceptionHandler({NoResourceFoundException.class, NoHandlerFoundException.class})
    public ResponseEntity<ApiResponse<Void>> handleNoHandler(Exception ex) {
        log.debug("No handler for request: {}", ex.getMessage());
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.error("요청한 경로를 찾을 수 없습니다.", "NOT_FOUND"));
    }

    /**
     * (BS-30 C4) UNIQUE 제약 위반 등 데이터 무결성 예외의 안전망. 서비스 레이어에서 잡지 못하고
     * 커밋 시점에 누출되더라도 500 대신 409로 응답한다(동일 자원 중복 생성 충돌).
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleDataIntegrity(DataIntegrityViolationException ex) {
        log.warn("Data integrity violation", ex);
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiResponse.error("요청이 기존 데이터와 충돌합니다.", "DATA_CONFLICT"));
    }

    /**
     * AI 인증 파이프라인 예외. 이미지 검증 실패는 4xx로, ai-service upstream 실패는 502로 매핑된다.
     * status 필드를 예외가 직접 보유하므로 여기서는 그대로 전달만 한다.
     */
    @ExceptionHandler(AiVerificationException.class)
    public ResponseEntity<ApiResponse<Void>> handleAiVerification(AiVerificationException ex) {
        HttpStatus status = ex.getStatus();
        if (status.is5xxServerError()) {
            log.error("AI verification server-side failure ({}): {}", status.value(), ex.getMessage(), ex);
        } else {
            log.warn("AI verification client-side failure ({}): {}", status.value(), ex.getMessage());
        }
        return ResponseEntity.status(status)
                .body(ApiResponse.error(ex.getMessage(), "AI_VERIFICATION_" + status.value()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleGeneral(Exception ex) {
        log.error("Unhandled exception", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.error("서버 내부 오류가 발생했습니다.", "INTERNAL_ERROR"));
    }
}
