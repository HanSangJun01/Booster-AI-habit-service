package com.booster.shared.common;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/**
 * 이미지 재사용 차단용 SHA-256 지문. 팀(ai_verification_results.image_sha256)과
 * 개인(personal_ai_attempts.image_sha256) 두 인증 경로가 같은 지문 형식을 쓴다.
 */
public final class Sha256 {

    private Sha256() {
    }

    public static String hex(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            // SHA-256은 모든 JVM 필수 알고리즘 — 여기 오면 런타임이 망가진 것.
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }
}
