# PhantomExpose — API Documentation

All requests go through the **API Gateway** at `http://localhost:8080`. The gateway validates the JWT (except `/api/auth/register`, `/api/auth/login`, `/actuator/health`) and forwards `X-User-Email`, `X-User-Role`, `X-User-Id` headers downstream.

Standard error shape (all services):
```json
{ "timestamp": "2026-07-15T10:00:00", "status": 400, "message": "Email already registered" }
```
Validation errors additionally return an `errors` map of `field -> message`.

---

## 1. Auth Service (`/api/auth`)

### POST `/api/auth/register`
Request:
```json
{
  "fullName": "Asha Rao",
  "email": "asha@utility.com",
  "password": "SecurePass123",
  "role": "UTILITY_OFFICER",
  "consumerNumber": null
}
```
Validation: `fullName`, `email` (valid format), `password` (min 8 chars), `role` (one of `ADMIN`, `UTILITY_OFFICER`, `FIELD_INSPECTOR`, `CONSUMER`) are required.

Response `201 Created`:
```json
{ "accessToken": "eyJhbGciOi...", "tokenType": "Bearer", "role": "UTILITY_OFFICER", "fullName": "Asha Rao", "expiresIn": 86400 }
```

### POST `/api/auth/login`
Request: `{ "email": "asha@utility.com", "password": "SecurePass123" }`
Response `200 OK`: same shape as register.
Errors: `401 Unauthorized` — invalid credentials, or a disabled/locked account.

---

## 2. Consumer Service (`/api/consumers`, `/api/meters`, `/api/transformers`)

### POST `/api/consumers`
```json
{
  "consumerNumber": "CN-1001",
  "fullName": "Ravi Kumar",
  "email": "ravi@example.com",
  "phone": "9876543210",
  "address": "12 MG Road",
  "region": "Hubballi-North",
  "consumerType": "RESIDENTIAL",
  "transformerId": 3
}
```
`201 Created` returns the created consumer with `id`.

### GET `/api/consumers` — list all
### GET `/api/consumers/{id}` — single consumer (Redis-cached)
### GET `/api/consumers/by-transformer/{transformerId}` — consumers on a transformer
### PUT `/api/consumers/{id}` — update profile
### PATCH `/api/consumers/{id}/assign-transformer/{transformerId}` — reassign transformer

### POST `/api/meters`
```json
{ "meterNumber": "MTR-5001", "meterType": "SMART", "initialReading": 0, "consumerId": 1 }
```

### POST `/api/transformers`
```json
{ "transformerCode": "TX-100", "distributionArea": "North Zone", "region": "Hubballi-North", "capacityKva": 500, "latitude": 15.36, "longitude": 75.12 }
```
### PATCH `/api/transformers/{id}/supplied-energy?value=15400.5` — update SCADA-fed total supplied energy

---

## 3. Meter Reading Service (`/api/readings`)

### POST `/api/readings`
```json
{
  "meterNumber": "MTR-5001",
  "consumerId": 1,
  "transformerId": 3,
  "readingDate": "2026-07-14",
  "readingType": "DAILY",
  "readingValueKwh": 1523.4,
  "estimated": false
}
```
On success, publishes a `meter-reading-created` Kafka event consumed by the detection-service, which evaluates the consumer in near real time.

### POST `/api/readings/bulk` — array of the same request body
### POST `/api/readings/bulk-csv` (multipart/form-data, field `file`) — CSV columns: `meterNumber,consumerId,transformerId,readingDate,readingType,readingValueKwh`
### GET `/api/readings/consumer/{consumerId}` — full history, newest first
### GET `/api/readings/consumer/{consumerId}/range?from=2026-01-01&to=2026-07-01`

---

## 4. Detection Service (`/api/detection`, `/api/alerts`)

### POST `/api/detection/evaluate/{consumerId}?transformerId=3`
Manually triggers the rule engine (normally automatic via Kafka). Returns:
```json
{
  "id": 42,
  "consumerId": 1,
  "transformerId": 3,
  "riskScore": 63,
  "riskCategory": "HIGH",
  "reasons": "[SUDDEN_CONSUMPTION_DROP] Consumption dropped 55.2% versus historical baseline (18.4 -> 8.2 kWh avg) | [FLAT_METER_READING] Meter reading unchanged for 20+ consecutive readings (range 0.10 kWh)",
  "evaluatedAt": "2026-07-15T09:12:00"
}
```

### GET `/api/detection/consumer/{consumerId}` — evaluation history

### GET `/api/alerts` — all alerts
### GET `/api/alerts/status/{status}` — filter by `OPEN|ASSIGNED|UNDER_INVESTIGATION|ESCALATED|CLOSED_CONFIRMED_THEFT|CLOSED_FALSE_POSITIVE`
### GET `/api/alerts/inspector/{inspectorId}` — an inspector's worklist
### PATCH `/api/alerts/{id}/assign` — `{ "inspectorId": 7 }`
### PATCH `/api/alerts/{id}/status` — `{ "status": "CLOSED_CONFIRMED_THEFT", "notes": "Bypass wire found on service line" }`

---

## 5. Notification Service
Consumes `alert-created` Kafka events internally and sends email via SMTP; no public endpoints beyond `/actuator/health` in this scaffold (extend with a `GET /api/notifications` history endpoint as needed).

---

## 6. Analytics Service (`/api/analytics`)

### GET `/api/analytics/dashboard`
```json
{
  "totalConsumers": 1200,
  "suspiciousConsumers": 87,
  "riskCategoryBreakdown": { "LOW": 1113, "MEDIUM": 52, "HIGH": 28, "CRITICAL": 7 },
  "alertStatusBreakdown": { "OPEN": 40, "ASSIGNED": 20, "CLOSED_CONFIRMED_THEFT": 12 },
  "openAlerts": 40,
  "closedConfirmedTheftCases": 12
}
```

### GET `/api/analytics/heatmap`
```json
[
  { "region": "Hubballi-North", "suspiciousCount": 14, "theftProbabilityPercent": 6.2 },
  { "region": "Hubballi-South", "suspiciousCount": 31, "theftProbabilityPercent": 11.4 }
]
```

---

## Error handling strategy (applies to every service)

| Status | Meaning | Example |
|---|---|---|
| 400 | Validation failure / bad request | Missing required field, malformed CSV row |
| 401 | Missing/invalid/expired JWT | No `Authorization` header, wrong password |
| 403 | Authenticated but role not permitted | Consumer trying to close an alert |
| 404 | Resource not found | Unknown consumer/transformer ID |
| 429 | Rate limit exceeded | More than the gateway's configured requests/sec |
| 500 | Unexpected server error | Logged with correlation ID, generic message returned to client |

Every service registers a `@RestControllerAdvice` (`GlobalExceptionHandler`) so error shapes stay consistent across the whole system, and none of them leak stack traces to the client.

## Role-based authorization matrix (enforced via gateway header + method-level checks in each service)

| Action | Admin | Utility Officer | Field Inspector | Consumer |
|---|---|---|---|---|
| Register/manage consumers, meters, transformers | ✅ | ✅ | ❌ | ❌ |
| Submit/bulk-upload readings | ✅ | ✅ | ✅ (field readings) | ❌ |
| View own consumption history | ✅ | ✅ | ✅ | ✅ (own only) |
| Trigger/view detection results | ✅ | ✅ | ✅ | ❌ |
| Assign alerts to inspectors | ✅ | ✅ | ❌ | ❌ |
| Update alert/investigation status | ✅ | ✅ | ✅ (assigned only) | ❌ |
| View analytics dashboard | ✅ | ✅ | ❌ | ❌ |
