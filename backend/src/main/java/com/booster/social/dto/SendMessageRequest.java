package com.booster.social.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class SendMessageRequest {

    // (BS-39 I6) 길이 상한. 예전엔 제한이 없어 10만자 메시지가 그대로 저장됐다.
    @NotBlank
    @Size(max = 1000, message = "메시지는 1000자를 넘을 수 없습니다.")
    private String content;
}
