package com.booster.shared.security;

import com.booster.user.repository.UserRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.lang.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Authorization: Bearer 헤더를 검증하고 SecurityContext에 인증을 채운다.
 * principal = userId(Long). 컨트롤러에서 @AuthenticationPrincipal Long userId 로 수신.
 */
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final String HEADER = "Authorization";
    private static final String PREFIX = "Bearer ";

    private final JwtTokenProvider jwtTokenProvider;
    private final UserRepository userRepository;

    @Override
    protected void doFilterInternal(@NonNull HttpServletRequest request,
                                    @NonNull HttpServletResponse response,
                                    @NonNull FilterChain filterChain)
            throws ServletException, IOException {
        String token = resolveToken(request);
        if (token != null && SecurityContextHolder.getContext().getAuthentication() == null) {
            Long userId = jwtTokenProvider.parseUserId(token);
            // (BS-39 I16) 토큰이 유효해도 비활성(탈퇴) 계정이면 인증을 채우지 않는다.
            // 예전엔 is_active를 로그인 시점에만 검사해, 탈퇴 후에도 발급된 JWT가 만료 전까지
            // 그대로 먹혀 좀비 세션(탈퇴 유저의 참여·체크인·코인 소비)이 가능했다.
            if (userId != null && userRepository.existsByIdAndActiveTrue(userId)) {
                var authentication = new UsernamePasswordAuthenticationToken(
                        userId, null, List.of());
                authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authentication);
            }
        }
        filterChain.doFilter(request, response);
    }

    private String resolveToken(HttpServletRequest request) {
        String header = request.getHeader(HEADER);
        if (header != null && header.startsWith(PREFIX)) {
            return header.substring(PREFIX.length());
        }
        return null;
    }
}
