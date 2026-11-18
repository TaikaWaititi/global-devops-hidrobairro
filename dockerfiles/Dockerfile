FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /build
COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN sed -i 's/\r$//' mvnw && chmod +x mvnw
COPY src src
RUN ./mvnw --batch-mode --no-transfer-progress clean verify

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S hidrobairro && adduser -S -G hidrobairro hidrobairro
WORKDIR /app
COPY --from=build --chown=hidrobairro:hidrobairro /build/target/gs-hidrobairro-0.0.1-SNAPSHOT.jar /app/app.jar
USER hidrobairro
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
