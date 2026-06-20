package com.booster;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class BoosterApplication {

    public static void main(String[] args) {
        SpringApplication.run(BoosterApplication.class, args);
    }
}
