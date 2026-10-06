# Build the fat jar on the official Gradle image (no wrapper download at build
# time), then run it on a slim JRE.
FROM gradle:8.14-jdk17 AS build
WORKDIR /src
COPY . .
RUN gradle buildFatJar --no-daemon

FROM eclipse-temurin:17-jre
COPY --from=build /src/build/libs/*-all.jar /app.jar
EXPOSE 9193
CMD ["java", "-jar", "/app.jar"]
