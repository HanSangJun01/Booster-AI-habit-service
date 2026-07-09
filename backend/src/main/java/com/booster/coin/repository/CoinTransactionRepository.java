package com.booster.coin.repository;

import com.booster.coin.domain.CoinTransaction;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CoinTransactionRepository extends JpaRepository<CoinTransaction, Long> {

    /**
     * (BS-30 F10) created_at 만으로 정렬하면 같은 시각(@CreationTimestamp) 다건이 페이지 경계에서
     * 순서가 흔들려 행이 누락/중복될 수 있다. id 를 tiebreaker 로 추가해 안정 정렬.
     */
    Page<CoinTransaction> findByUserIdOrderByCreatedAtDescIdDesc(Long userId, Pageable pageable);
}
