package com.booster.challengecheckin.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;
import java.util.List;

public record AiServiceVerdict(
        boolean passed,
        @JsonProperty("confidence_score") BigDecimal confidenceScore,
        @JsonProperty("detected_labels") List<String> detectedLabels,
        @JsonProperty("model_name") String modelName,
        String reason,
        @JsonProperty("storage_key") String storageKey,
        @JsonProperty("raw_response") Object rawResponse
) {
}
