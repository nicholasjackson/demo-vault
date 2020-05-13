FROM openjdk:12 as build

WORKDIR /src
COPY . /src

RUN ./gradlew build

FROM openjdk:12

RUN mkdir /app
WORKDIR /app

COPY --from=build /src/build/libs/spring-boot-payments-0.1.0.jar /app/spring-boot-payments-0.1.0.jar

ENTRYPOINT ["java", "-jar", "/app/spring-boot-payments-0.1.0.jar"]