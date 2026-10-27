FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app
COPY . .
RUN mvn -q -DskipTests package
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8083
ENTRYPOINT ["java","-jar","app.jar"]
