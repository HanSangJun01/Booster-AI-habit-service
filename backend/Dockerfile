# ===== 1단계: 빌드 (JDK로 gradle 빌드) =====
FROM eclipse-temurin:23-jdk AS build

WORKDIR /app

# gradle wrapper와 빌드 설정 먼저 복사 (의존성 캐싱을 위해)
COPY gradlew .
COPY gradle gradle
COPY build.gradle settings.gradle ./

# 의존성 미리 다운로드 (소스 변경 시 이 레이어는 캐시 재사용)
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon || true

# 소스 복사 후 빌드 (테스트는 제외하고 빠르게 jar 생성)
COPY src src
RUN ./gradlew clean bootJar --no-daemon -x test

# ===== 2단계: 실행 (가벼운 JRE로 실행만) =====
FROM eclipse-temurin:23-jre AS runtime

WORKDIR /app

# 보안: root가 아닌 일반 유저로 실행
RUN groupadd -r spring && useradd -r -g spring spring

# 빌드 단계에서 만든 jar만 복사
COPY --from=build /app/build/libs/*.jar app.jar

USER spring

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
