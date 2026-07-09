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

@RestController
@RequestMapping("/api/personal/check-in")
@RequiredArgsConstructor
public class PersonalCheckInController {

    private final PersonalCheckInService personalCheckInService;

    @PostMapping
    public ResponseEntity<CheckInResponse> checkIn(@AuthenticationPrincipal Long userId,
                                                   @Valid @RequestBody CheckInRequest request) {
        CheckInResponse response = personalCheckInService.checkIn(userId, request.lat(), request.lng());
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/today")
    public ResponseEntity<TodayStatusResponse> today(@AuthenticationPrincipal Long userId) {
        return ResponseEntity.ok(personalCheckInService.getToday(userId));
    }
}
