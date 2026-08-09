package com.booster.challengecheckin.controller;

import com.booster.challengecheckin.dto.AiVerificationResponse;
import com.booster.challengecheckin.service.AiVerificationService;
import com.booster.shared.common.ApiResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/verification-submissions")
@RequiredArgsConstructor
public class AiVerificationController {

    private final AiVerificationService aiVerificationService;

    @PostMapping(
            value = "/{submissionId}/ai-verification",
            consumes = MediaType.MULTIPART_FORM_DATA_VALUE
    )
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<AiVerificationResponse> verify(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long submissionId,
            @RequestParam("category") String category,
            @RequestPart("image") MultipartFile image
    ) {
        return ApiResponse.success(
                aiVerificationService.verifyAndSave(userId, submissionId, category, image)
        );
    }
}
