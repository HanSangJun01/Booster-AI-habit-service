package com.booster.coin.repository;

import com.booster.coin.domain.CoinTransaction;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CoinTransactionRepository extends JpaRepository<CoinTransaction, Long> {

    Page<CoinTransaction> findByUserIdOrderByCreatedAtDesc(Long userId, Pageable pageable);
}
