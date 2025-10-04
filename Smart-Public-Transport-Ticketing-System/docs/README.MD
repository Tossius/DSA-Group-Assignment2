# Smart Public Transport Ticketing System

## Project Structure Overview

```
transport-ticketing-system/
├── README.md                  # Main documentation
├── .gitignore                 # Files to ignore in git
├── docker-compose.yml         # Defines all services (DB, Kafka, apps)
│
├── docs/                      # Documentation folder
│   ├── architecture.md        # System design diagram
│   ├── api-documentation.md   # API endpoints documentation
│   └── database-schema.md     # Database table designs
│
├── scripts/                   # Utility scripts
│   ├── init-db.sql            # Database setup SQL
│   ├── create-kafka-topics.sh # Creates Kafka topics
│   └── start-services.sh      # Starts everything
│
├── passenger-service/         # Passenger management service
│   ├── Ballerina.toml         # Ballerina project config
│   ├── main.bal               # Main service code
│   ├── database.bal           # Database operations
│   ├── types.bal              # Data types/records
│   ├── Dockerfile             # Docker container definition
│   └── Config.toml            # Configuration file
│
├── transport-service/         # Transport management service
│   ├── Ballerina.toml
│   ├── main.bal
│   ├── database.bal
│   ├── kafka_producer.bal     # Kafka message sending
│   ├── types.bal
│   ├── Dockerfile
│   └── Config.toml
│
├── ticketing-service/         # Ticketing service
│   ├── Ballerina.toml
│   ├── main.bal
│   ├── database.bal
│   ├── kafka_producer.bal
│   ├── kafka_consumer.bal     # Kafka message receiving
│   ├── types.bal
│   ├── Dockerfile
│   └── Config.toml
│
├── payment-service/           # Payment processing service
│   ├── Ballerina.toml
│   ├── main.bal
│   ├── database.bal
│   ├── kafka_consumer.bal
│   ├── kafka_producer.bal
│   ├── types.bal
│   ├── Dockerfile
│   └── Config.toml
│
├── notification-service/      # Notification delivery service
│   ├── Ballerina.toml
│   ├── main.bal
│   ├── database.bal
│   ├── kafka_consumer.bal
│   ├── types.bal
│   ├── Dockerfile
│   └── Config.toml
│
└── admin-service/             # Admin management service
    ├── Ballerina.toml
    ├── main.bal
    ├── database.bal
    ├── kafka_producer.bal
    ├── types.bal
    ├── Dockerfile
    └── Config.toml
```

### Root Level Files

- **.gitignore**  
  Specifies files and folders to exclude from version control.

- **docker-compose.yml**  
  Defines and manages all containers (PostgreSQL, Kafka, services).  
  Running this file starts the entire system stack.

- **README.md**  
  Main project documentation.

### scripts/

- **init-db.sql**  
  Sets up all database tables (users, routes, trips, tickets, payments, notifications).  
  Runs automatically when PostgreSQL starts.

- **create-kafka-topics.sh**  
  Creates Kafka message channels (e.g., ticket.requests, payments.processed, schedule.updates).

- **start-services.sh**  
  Convenience script to start all services.

### docs/

- **architecture.md**  
  System design diagram and architecture explanation.

- **api-documentation.md**  
  Documentation for all REST API endpoints.

- **database-schema.md**  
  Database table designs and relationships.

### Service Directory Structure (applies to each service)

- **Ballerina.toml**  
  Project configuration and dependencies (PostgreSQL, Kafka libraries).

- **main.bal**  
  Main service code, defines HTTP endpoints (REST API), handles requests.

- **database.bal**  
  Database operations (e.g., `saveUser()`, `getTickets()`, `updateTrip()`).

- **types.bal**  
  Data structure definitions (e.g., `type User record { int id; string email; string name; };`).

- **kafka_producer.bal**  
  Sends messages to Kafka (for services that produce events).

- **kafka_consumer.bal**  
  Receives messages from Kafka (for services that consume events).

- **Dockerfile**  
  Instructions to package the service into a container.

- **Config.toml**  
  Service-specific settings (database connection, Kafka server address, port numbers).