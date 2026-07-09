package com.booster.challengecheckin.service;

import com.booster.config.CacheConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import org.springframework.cache.caffeine.CaffeineCache;
import org.springframework.stereotype.Component;

/**
 * team-detail 캐시(키: "challengeId_userId")를 챌린지 단위로 무효화한다.
 * 한 참가자의 체크인은 양 팀 모두의 team-detail 응답을 바꾸므로, 해당 챌린지의 모든 키를 evict 해야 한다.
 * Spring @CacheEvict은 와일드카드/prefix를 지원하지 않아 네이티브 Caffeine 맵에서 prefix로 제거한다.
 * 단일 인스턴스 로컬 캐시 전제 — 멀티 인스턴스면 인스턴스 간 evict 전파(공유 캐시/pub-sub)가 필요.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class TeamDetailCacheEvictor {

    private final CacheManager cacheManager;

    public void evictChallenge(Long challengeId) {
        Cache cache = cacheManager.getCache(CacheConfig.TEAM_DETAIL);
        if (!(cache instanceof CaffeineCache caffeineCache)) {
            return;
        }
        String prefix = challengeId + "_";
        boolean removed = caffeineCache.getNativeCache().asMap().keySet()
                .removeIf(key -> key instanceof String s && s.startsWith(prefix));
        if (removed) {
            log.debug("[TeamDetailCacheEvictor] evicted team-detail cache for challengeId={}", challengeId);
        }
    }
}
