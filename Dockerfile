# syntax=docker/dockerfile:1
FROM maven:3-amazoncorretto-25 AS build
ARG SOURCE_DATE_EPOCH
WORKDIR /workspace
COPY .mvn/ .mvn/
COPY --chmod=755 mvnw .
COPY pom.xml .
COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw --batch-mode --no-transfer-progress \
    ${SOURCE_DATE_EPOCH:+"-Dproject.build.outputTimestamp=$SOURCE_DATE_EPOCH"} verify

FROM amazoncorretto:25
LABEL org.opencontainers.image.authors="m.buechner@dnb.de"
ENV TZ=Europe/Berlin
WORKDIR /opt/iiif
COPY --from=build /workspace/target/iiif.jar /workspace/target/bom.json ./
USER 10001:10001
EXPOSE 8080
CMD ["java", "-jar", "iiif.jar"]
