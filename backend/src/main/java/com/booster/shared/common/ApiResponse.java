package com.booster.shared.common;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Getter;

/**
 * MVP_API_SPEC §2.2/2.3 공통 응답 엔벨로프 (A/B축 통합 단일 규약).
 *
 * 성공: {@code {"success": true, "message"?: ..., "data"?: ...}}
 * 실패: {@code {"success": false, "message": ..., "errorCode": ...}}
 *
 * null 필드는 직렬화에서 생략한다(성공 응답엔 errorCode 없음, 에러 응답엔 data 없음).
 */
@Getter
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiResponse<T> {

    private final boolean success;
    private final String message;
    private final T data;
    private final String errorCode;

    private ApiResponse(boolean success, String message, T data, String errorCode) {
        this.success = success;
        this.message = message;
        this.data = data;
        this.errorCode = errorCode;
    }

    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(true, null, data, null);
    }

    public static <T> ApiResponse<T> success(String message, T data) {
        return new ApiResponse<>(true, message, data, null);
    }

    public static <T> ApiResponse<T> error(String message, String errorCode) {
        return new ApiResponse<>(false, message, null, errorCode);
    }
}
