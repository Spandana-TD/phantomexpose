# PhantomExpose — Entity Relationship Diagram

```mermaid
erDiagram
    USERS ||--o| CONSUMERS : "consumer_number (cross-service link)"
    TRANSFORMERS ||--o{ CONSUMERS : supplies
    CONSUMERS ||--|| METERS : owns
    CONSUMERS ||--o{ METER_READINGS : generates
    METERS ||--o{ METER_READINGS : records
    TRANSFORMERS ||--o{ METER_READINGS : aggregates
    CONSUMERS ||--o{ DETECTION_RESULTS : evaluated_for
    DETECTION_RESULTS ||--|| ALERTS : raises
    ALERTS ||--o{ NOTIFICATIONS : triggers
    USERS ||--o{ ALERTS : "assigned_inspector_id"

    USERS {
        bigint id PK
        string full_name
        string email UK
        string password
        string consumer_number UK
        string role
        boolean enabled
    }

    TRANSFORMERS {
        bigint id PK
        string transformer_code UK
        string distribution_area
        string region
        double capacity_kva
        double total_supplied_energy_kwh
    }

    CONSUMERS {
        bigint id PK
        string consumer_number UK
        string full_name
        string region
        string consumer_type
        bigint transformer_id FK
        boolean active
    }

    METERS {
        bigint id PK
        string meter_number UK
        string meter_type
        double initial_reading
        bigint consumer_id FK
    }

    METER_READINGS {
        bigint id PK
        string meter_number
        bigint consumer_id FK
        bigint transformer_id FK
        date reading_date
        string reading_type
        double reading_value_kwh
        double consumption_kwh
    }

    DETECTION_RESULTS {
        bigint id PK
        bigint consumer_id FK
        bigint transformer_id FK
        int risk_score
        string risk_category
        string reasons
        timestamp evaluated_at
    }

    ALERTS {
        bigint id PK
        bigint consumer_id FK
        bigint detection_result_id FK
        string risk_category
        string status
        bigint assigned_inspector_id FK
        timestamp created_at
    }

    NOTIFICATIONS {
        bigint id PK
        bigint alert_id FK
        string type
        string channel
        boolean sent
    }
```

## Design notes

- **Database-per-service**: each microservice owns its schema (`phantomexpose_auth`, `_consumer`, `_meter`, `_detection`, `_notification`). Cross-service references (e.g. `consumer_id` in `meter_readings`) are logical foreign keys resolved via REST/Feign calls, not physical DB foreign keys, since services do not share a database in production. The `analytics-service` is the one exception that reads directly off the `phantomexpose_detection` database for query performance — an accepted CQRS-style trade-off for a dashboard that needs cheap aggregate reads.
- **Indexing strategy**: composite indexes are placed on `(meter_number, reading_date)` and `(consumer_id, reading_date)` in `meter_readings` since the detection engine's hot path is "get last N readings for a consumer ordered by date." `alerts.status` and `alerts.assigned_inspector_id` are indexed to support the inspector's worklist queries. `detection_results.risk_category` supports fast dashboard aggregation.
