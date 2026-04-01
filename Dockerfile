FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

COPY build/lib/ /app/lib/
COPY build/*.jar /app/
COPY build/app/ /app/app/
COPY build/quarkus/ /app/quarkus/

EXPOSE 8080

ENV APP_API_LIMIT=350
ENV APP_API_TIMEOUT=6000

CMD ["java", "-jar", "quarkus-run.jar"]
