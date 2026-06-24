package com.booster.shared.common;

/** bs-25 에러 응답 포맷: { "code": "...", "message": "..." } */
public record ErrorResponse(String code, String message) {
}
