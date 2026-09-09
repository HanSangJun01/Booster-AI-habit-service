package com.booster.personalcheckin.controller;

import com.booster.personalcheckin.dto.CheckInRequest;
import com.booster.personalcheckin.dto.CheckInResponse;
import com.booster.personalcheckin.dto.TodayStatusResponse;
import com.booster.personalcheckin.service.PersonalCheckInService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.booster.personalcheckin.dto.PersonalAiVerificationResponse;
import com.booster.personalcheckin.service.PersonalAiVerificationService;
import org.springframework.http.MediaType;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;

@RestController
@RequestMapping("/api/personal/check-in")
@RequiredArgsConstructor
public class PersonalCheckInController {

    private final PersonalCheckInService personalCheckInService;
    private final PersonalAiVerificationService personalAiVerificationService;

    @PostMapping
    public ResponseEntity<CheckInResponse> checkIn(@AuthenticationPrincipal Long userId,
                                                   @Valid @RequestBody CheckInRequest request) {
        CheckInResponse response = personalCheckInService.checkIn(userId, request.lat(), request.lng());
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    /**
     * AI 사진 인증 (2단계). 인증 방식이 AI 를 포함하는 목표에서, 체크인으로 만들어진
     * PENDING 건에 사진을 올려 확정한다. checkInId 는 체크인 응답의 {@code checkInId} 다.
     */
    @PostMapping(value = "/{checkInId}/ai-verification", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<PersonalAiVerificationResponse> verifyByAi(
            @AuthenticationPrincipal Long userId,
            @PathVariable Long checkInId,
            @RequestParam("category") String category,
            @RequestPart("image") MultipartFile image) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(personalAiVerificationService.verifyAndSave(userId, checkInId, category, image));
    }

    @GetMapping("/today")
    public ResponseEntity<TodayStatusResponse> today(@AuthenticationPrincipal Long userId) {
        return ResponseEntity.ok(personalCheckInService.getToday(userId));
    }
}
