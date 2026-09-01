package com.booster.dashboard.controller;

import com.booster.dashboard.dto.DashboardResponse;
import com.booster.dashboard.service.DashboardService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.time.YearMonth;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/dashboard")
@RequiredArgsConstructor
public class DashboardController {

    private final DashboardService dashboardService;

    /**
     * 홈 대시보드.
     *
     * @param month 캘린더로 볼 달(yyyyMM, 예 202608). 생략하면 이번 달.
     *              달력을 넘겨 보는 데 쓴다 — 없으면 앱이 지난 달 기록을 볼 방법이 없다.
     */
    @GetMapping("/home")
    public ResponseEntity<DashboardResponse> home(
            @AuthenticationPrincipal Long userId,
            @RequestParam(required = false)
            @DateTimeFormat(pattern = "yyyyMM") YearMonth month) {
        return ResponseEntity.ok(
                dashboardService.getHome(userId, month == null ? null : month.atDay(1)));
    }
}
