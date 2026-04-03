# Используем легковесный образ с Java 21
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Это перенесет сразу /lib, /app, /quarkus и quarkus-run.jar
COPY build/quarkus-app/ .

EXPOSE 8080

# Переменные окружения
ENV APP_API_LIMIT=350
ENV APP_API_TIMEOUT=6000

# Запуск
CMD ["java", "-jar", "quarkus-run.jar"]
