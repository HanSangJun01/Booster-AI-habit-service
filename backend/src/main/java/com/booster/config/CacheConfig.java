package com.booster.config;

import com.booster.challengecheckin.service.TeamDetailViewService;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.github.benmanes.caffeine.cache.CacheLoader;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.caffeine.CaffeineCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;
import java.util.List;

/**
 * Caffeine 로컬(in-process) 캐시 설정.
 *
 * team-detail은 라이브 체크인 뷰라:
 *  - refreshAfterWrite(10s): 10초 지나면 만료가 아니라 "낡음" 표시 → 다음 조회는 낡은 값을 즉시 반환하고
 *    백그라운드에서 단 1개 스레드만 CacheLoader로 재계산 → TTL 만료 herd(stampede) 방지.
 *  - expireAfterWrite(60s): 60초 동안 조회 안 된 cold 키는 완전 제거(메모리·최대 staleness 제한).
 *  - 체크인 write는 TeamDetailCacheEvictor가 즉시 evict(하드 삭제) → 다음 조회는 동기 재계산으로 최신 반영.
 *
 * 단일 인스턴스 로컬 캐시 전제 — 멀티 인스턴스면 인스턴스 간 evict 전파(공유 캐시/pub-sub)로 승격 검토.
 */
@Configuration
@EnableCaching
public class CacheConfig {

    /** 팀 비교 뷰 캐시 이름. */
    public static final String TEAM_DETAIL = "teamDetail";

    @Bean
    public CacheManager cacheManager(ObjectProvider<TeamDetailViewService> teamDetailService) {
        // refreshAfterWrite 재계산기: 캐시 키("challengeId_userId")를 파싱해 비캐시 계산 메서드를 호출.
        CacheLoader<Object, Object> loader = key -> {
            String[] parts = ((String) key).split("_", 2);
            return teamDetailService.getObject()
                    .computeTeamComparison(Long.valueOf(parts[0]), Long.valueOf(parts[1]));
        };

        // 순서 중요: refreshAfterWrite는 LoadingCache를 요구하므로, setCaffeine 전에 loader를 먼저 설정한다.
        CaffeineCacheManager manager = new CaffeineCacheManager();
        manager.setCacheLoader(loader);
        manager.setCaffeine(Caffeine.newBuilder()
                .refreshAfterWrite(Duration.ofSeconds(10))
                .expireAfterWrite(Duration.ofSeconds(60))
                .maximumSize(10_000)
                .recordStats());
        manager.setCacheNames(List.of(TEAM_DETAIL));
        return manager;
    }
}
