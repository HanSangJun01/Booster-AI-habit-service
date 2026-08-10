package com.booster.weeklygoal.controller;

import com.booster.coin.service.CoinService;
import com.booster.weeklygoal.dto.RecoveryTicketResponse;
import com.booster.weeklygoal.dto.WeeklyGoalResponse;
import com.booster.weeklygoal.dto.WeeklyGoalUpdateRequest;
import com.booster.weeklygoal.service.RecoveryTicketService;
import com.booster.weeklygoal.service.WeeklyGoalService;
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

/**
 * 주간 목표 · 구제권 API (A축).
 *
 * <pre>
 *   GET  /api/personal/weekly-goal        목표·이번 주 진행률·구제권 현황
 *   PUT  /api/personal/weekly-goal        목표 변경 예약(다음 주부터 적용)
 *   POST /api/personal/recovery-tickets   구제권 코인 구매
 * </pre>
 */
@RestController
@RequestMapping("/api/personal")
@RequiredArgsConstructor
public class WeeklyGoalController {

    private final WeeklyGoalService weeklyGoalService;
    private final RecoveryTicketService recoveryTicketService;
    private final CoinService coinService;

    @GetMapping("/weekly-goal")
    public ResponseEntity<WeeklyGoalResponse> getWeeklyGoal(@AuthenticationPrincipal Long userId) {
        return ResponseEntity.ok(weeklyGoalService.getStatus(userId));
    }

    @PutMapping("/weekly-goal")
    public ResponseEntity<WeeklyGoalResponse> updateWeeklyGoal(
            @AuthenticationPrincipal Long userId,
            @Valid @RequestBody WeeklyGoalUpdateRequest request) {
        return ResponseEntity.ok(weeklyGoalService.reserveTarget(userId, request.targetDays()));
    }

    @PostMapping("/recovery-tickets")
    public ResponseEntity<RecoveryTicketResponse> purchaseTicket(@AuthenticationPrincipal Long userId) {
        int tickets = recoveryTicketService.purchase(userId);
        return ResponseEntity.status(HttpStatus.CREATED).body(new RecoveryTicketResponse(
                tickets, recoveryTicketService.getTicketPrice(), coinService.getBalance(userId)));
    }
}
