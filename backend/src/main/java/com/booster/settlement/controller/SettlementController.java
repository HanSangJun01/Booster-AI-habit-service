package com.booster.settlement.controller;

import com.booster.settlement.dto.SettlementResultResponse;
import com.booster.settlement.repository.SettlementRepository;
import com.booster.shared.common.ApiResponse;
import com.booster.shared.common.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/challenges")
@RequiredArgsConstructor
public class SettlementController {

    private final SettlementRepository settlementRepository;

    @GetMapping("/{challengeId}/result")
    public ApiResponse<SettlementResultResponse> getResult(@PathVariable Long challengeId) {
        return settlementRepository.findByChallengeId(challengeId)
                .map(s -> ApiResponse.success(SettlementResultResponse.from(s)))
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Settlement not found for challengeId: " + challengeId));
    }
}
