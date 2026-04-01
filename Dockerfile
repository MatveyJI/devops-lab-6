# Используем легковесный образ с Java 21
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Копируем всё содержимое папки quarkus-app, которую создал Gradle
# Это перенесет сразу /lib, /app, /quarkus и quarkus-run.jar
COPY build/quarkus-app/ .

EXPOSE 8080

# Переменные окружения
ENV APP_API_LIMIT=350
ENV APP_API_TIMEOUT=6000

# Запуск. В этой папке файл называется quarkus-run.jar
CMD ["java", "-jar", "quarkus-run.jar"]
