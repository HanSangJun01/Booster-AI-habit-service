package com.booster.shared.common;

import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
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

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleGeneral(Exception ex) {
        log.error("Unhandled exception", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.error("서버 내부 오류가 발생했습니다.", "INTERNAL_ERROR"));
    }
}
