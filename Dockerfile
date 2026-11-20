# syntax=docker/dockerfile:1
FROM eclipse-temurin:25-jdk-alpine AS build
WORKDIR /workspace
COPY .mvn/ .mvn/
COPY --chmod=755 mvnw .
COPY pom.xml .
COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 ./mvnw --batch-mode --no-transfer-progress verify

FROM eclipse-temurin:25-jre-alpine
LABEL org.opencontainers.image.authors="m.buechner@dnb.de"
ENV TZ=Europe/Berlin
WORKDIR /opt/iiif
COPY --from=build /workspace/target/iiif.jar iiif.jar
USER 10001:10001
EXPOSE 8080
CMD ["java", "-jar", "iiif.jar"]
