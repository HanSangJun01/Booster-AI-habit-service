package com.booster.shared.common;

public class InsufficientCoinException extends RuntimeException {

    public InsufficientCoinException(long required, long available) {
        super("Insufficient coins: required " + required + ", available " + available);
    }
}
