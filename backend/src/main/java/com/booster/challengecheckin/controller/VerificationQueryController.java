package com.booster.challengecheckin.controller;

import com.booster.challengecheckin.dto.VerificationSubmissionDetail;
import com.booster.challengecheckin.service.VerificationQueryService;
import com.booster.shared.common.ApiResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 인증 결과 상세 조회 (MVP_API_SPEC §9.2). */
@RestController
@RequestMapping("/api/check-ins")
@RequiredArgsConstructor
public class VerificationQueryController {

    private final VerificationQueryService verificationQueryService;

    @GetMapping("/{checkInId}/verification-submissions")
    public ApiResponse<List<VerificationSubmissionDetail>> submissions(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long checkInId) {
        return ApiResponse.success(verificationQueryService.getSubmissions(userId, checkInId));
    }
}
