package com.booster.personallocation.controller;

import com.booster.personallocation.dto.LocationRequest;
import com.booster.personallocation.dto.LocationResponse;
import com.booster.personallocation.service.PersonalLocationService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users/me/location")
@RequiredArgsConstructor
public class PersonalLocationController {

    private final PersonalLocationService personalLocationService;

    @PostMapping
    public ResponseEntity<LocationResponse> register(@AuthenticationPrincipal Long userId,
                                                     @Valid @RequestBody LocationRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(personalLocationService.register(userId, request));
    }

    @PutMapping
    public ResponseEntity<LocationResponse> update(@AuthenticationPrincipal Long userId,
                                                   @Valid @RequestBody LocationRequest request) {
        return ResponseEntity.ok(personalLocationService.update(userId, request));
    }

    @GetMapping
    public ResponseEntity<LocationResponse> get(@AuthenticationPrincipal Long userId) {
        return ResponseEntity.ok(personalLocationService.get(userId));
    }
}
