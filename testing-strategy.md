# PhantomExpose — Testing Strategy

## 1. Test pyramid

```
        ┌───────────────────────────┐
        │   E2E (Postman/Newman,    │   few, slow, high confidence
        │   Cypress on frontend)    │
        ├───────────────────────────┤
        │ Integration (Testcontainers│  moderate volume
        │ Postgres+Kafka per service)│
        ├───────────────────────────┤
        │      Unit tests            │  many, fast, cheap
        │ (services, rules, mappers) │
        └───────────────────────────┘
```

## 2. Unit testing

- **Detection rules** are the highest-value unit test target since they encode the core business logic. Each rule (`SuddenConsumptionDropRule`, `NeighborhoodDeviationRule`, `TransformerEnergyMismatchRule`, `FlatMeterReadingRule`, `AbnormalUsagePatternRule`, `MeterResetDetectionRule`) is a plain Spring `@Component` implementing `DetectionRule`, so it can be instantiated directly in a JUnit 5 test with a hand-built `RuleContext` — no Spring context needed.
  ```java
  @Test
  void firesWhenConsumptionDropsBeyondThreshold() {
      var rule = new SuddenConsumptionDropRule();
      ReflectionTestUtils.setField(rule, "dropThresholdPercent", 40.0);
      var ctx = new DetectionRule.RuleContext(1L, 3L, buildDecliningReadings(), List.of(), null, null);
      var outcome = rule.evaluate(ctx);
      assertThat(outcome.isTriggered()).isTrue();
  }
  ```
- **DetectionEngine** is tested with mocked `MeterReadingClient`/`ConsumerClient` (Mockito) and a mix of rule beans to verify score aggregation and category thresholds (LOW < 20 ≤ MEDIUM < 45 ≤ HIGH < 70 ≤ CRITICAL).
- **AuthService**: password hashing/matching, duplicate-email rejection, JWT claim contents — using an in-memory `UserRepository` mock.
- **Mappers/DTO conversions**: verified with plain input/output assertions; MapStruct-generated mappers are tested for null-safety.

Target: ≥80% line coverage on `service` and `rules` packages (JaCoCo, enforced via Maven `jacoco-maven-plugin` with a build-breaking threshold in CI).

## 3. Integration testing (Testcontainers)

Each service spins up ephemeral Postgres (and Kafka where relevant) containers for its `@SpringBootTest` integration suite, so tests run against the real driver/schema instead of an in-memory substitute like H2 that can mask SQL dialect issues.

```java
@SpringBootTest
@Testcontainers
class MeterReadingServiceIntegrationTest {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Container
    static KafkaContainer kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.6.1"));

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", postgres::getJdbcUrl);
        r.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
    }

    @Test
    void recordingAReadingPublishesKafkaEvent() { /* ... */ }
}
```

Key integration scenarios per service:
- **auth-service**: register → login → JWT round-trip verified against `SecurityConfig`.
- **consumer-service**: consumer/meter/transformer CRUD + Redis cache eviction on update.
- **meter-reading-service**: bulk CSV upload parses correctly and each row publishes a Kafka event; malformed rows are rejected with a 400.
- **detection-service**: an inbound `meter-reading-created` event triggers evaluation and (when risk ≥ MEDIUM) an `alert-created` event and a persisted `Alert` row.
- **notification-service**: consuming an `alert-created` event results in a `Notification` row with `sent=true` (mocking `JavaMailSender` with GreenMail or a Mockito bean).

## 4. Contract testing

Feign clients between `detection-service` ↔ `consumer-service`/`meter-reading-service` are covered with **Spring Cloud Contract** (or lightweight WireMock stubs) so a breaking response-shape change in a producer service fails the consumer's build before deployment, not in production.

## 5. End-to-end / API testing

A Postman collection (exportable from `docs/API.md`) drives the full happy path through the gateway: register → login → register consumer → register meter/transformer → submit readings → wait for Kafka-driven detection → verify alert appears → assign inspector → close alert → check analytics dashboard reflects the change. Run via `newman run PhantomExpose.postman_collection.json` in CI against a docker-compose'd stack.

## 6. Frontend testing

- **Component tests**: React Testing Library for `StatCard`, `ProtectedRoute`, form validation on `Login`/`Register`/`Consumers` dialogs.
- **E2E**: Cypress covering login, consumer registration, reading submission, and alert status transitions against a running docker-compose stack.

## 7. Performance & load testing

- k6 or Gatling script simulating bursty smart-meter ingestion (thousands of `POST /api/readings` per minute) to validate the Kafka-driven detection pipeline keeps up and the gateway's Redis rate limiter behaves as configured.
- Load test the `analytics-service` dashboard endpoint under concurrent access to validate the Redis cache (`@Cacheable`) is effective.

## 8. CI pipeline (suggested GitHub Actions stages)

1. `mvn -pl <changed-service> -am test` (unit) on every push
2. `mvn verify` (integration, Testcontainers) on PRs to `main`
3. `npm run build` + Cypress smoke run for frontend
4. `docker compose build` to catch Dockerfile regressions
5. JaCoCo coverage gate + SonarQube static analysis
6. On merge to `main`: build and push images, then deploy to staging
