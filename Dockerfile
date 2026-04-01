# Используем легковесный образ с Java 21
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Копируем структуру Quarkus fast-jar (она создается после ./gradlew build)
COPY build/quarkus-app/lib/ /app/lib/
COPY build/quarkus-app/*.jar /app/
COPY build/quarkus-app/app/ /app/app/
COPY build/quarkus-app/quarkus/ /app/quarkus/

EXPOSE 8080

# Переменные окружения по умолчанию (могут быть переопределены в k8s)
ENV APP_API_LIMIT=350
ENV APP_API_TIMEOUT=6000

# Запуск основного jar-файла Quarkus
CMD ["java", "-jar", "quarkus-run.jar"]