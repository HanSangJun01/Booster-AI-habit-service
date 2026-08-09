package com.booster.shared.common;

public class ChallengeFullException extends RuntimeException {

    public ChallengeFullException(Long challengeId) {
        super("Challenge is already full: challengeId=" + challengeId);
    }
}
