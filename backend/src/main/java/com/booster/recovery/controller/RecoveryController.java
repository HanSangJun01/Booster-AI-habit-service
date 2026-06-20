package com.booster.recovery.controller;

import com.booster.recovery.dto.RecoveryCheckInRequest;
import com.booster.recovery.dto.RecoveryResultResponse;
import com.booster.recovery.dto.RecoveryStatusResponse;
import com.booster.recovery.service.RecoveryService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/personal/recovery")
@RequiredArgsConstructor
public class RecoveryController {

    private final RecoveryService recoveryService;

    @GetMapping("/status")
    public ResponseEntity<RecoveryStatusResponse> status(@AuthenticationPrincipal Long userId) {
        return ResponseEntity.ok(recoveryService.getStatus(userId));
    }

    @PostMapping
    public ResponseEntity<RecoveryResultResponse> perform(@AuthenticationPrincipal Long userId,
                                                          @Valid @RequestBody RecoveryCheckInRequest request) {
        return ResponseEntity.ok(recoveryService.performRecovery(userId, request.lat(), request.lng()));
    }
}
