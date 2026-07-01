package com.booster.user.controller;

import com.booster.user.dto.CoinHistoryResponse;
import com.booster.user.dto.MyPageResponse;
import com.booster.user.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users/me")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @GetMapping
    public ResponseEntity<MyPageResponse> myPage(@AuthenticationPrincipal Long userId) {
        return ResponseEntity.ok(userService.getMyPage(userId));
    }

    /** 코인 내역 페이징. size 상한 100. (BS-30 F9) 잘못된 page/size로 500 나지 않도록 클램프. */
    private static final int MAX_PAGE_SIZE = 100;

    @GetMapping("/coins")
    public ResponseEntity<CoinHistoryResponse> coins(@AuthenticationPrincipal Long userId,
                                                     @RequestParam(defaultValue = "0") int page,
                                                     @RequestParam(defaultValue = "20") int size) {
        int safePage = Math.max(0, page);
        int safeSize = Math.min(Math.max(1, size), MAX_PAGE_SIZE);
        Pageable pageable = PageRequest.of(safePage, safeSize);
        return ResponseEntity.ok(userService.getCoinHistory(userId, pageable));
    }

    @DeleteMapping
    public ResponseEntity<Void> withdraw(@AuthenticationPrincipal Long userId) {
        userService.withdraw(userId);
        return ResponseEntity.noContent().build();
    }
}
