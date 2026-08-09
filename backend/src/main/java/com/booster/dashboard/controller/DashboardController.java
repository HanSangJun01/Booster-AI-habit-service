package com.booster.dashboard.controller;

import com.booster.dashboard.dto.DashboardResponse;
import com.booster.dashboard.service.DashboardService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/dashboard")
@RequiredArgsConstructor
public class DashboardController {

    private final DashboardService dashboardService;

    @GetMapping("/home")
    public ResponseEntity<DashboardResponse> home(@AuthenticationPrincipal Long userId) {
        return ResponseEntity.ok(dashboardService.getHome(userId));
    }
}
