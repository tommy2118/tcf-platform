# TCF Platform - Complete System Orchestration

## Overview
The TCF Platform repository orchestrates all TCF microservices into a complete Tiny Code Factory system. This is the main entry point for running the entire platform locally or deploying to production.

## Architecture

### Service Map
```
┌─────────────────────────────────────────────────────────┐
│                    TCF Gateway (3000)                    │
│                   (API Gateway & Router)                 │
└─────────────────────────┬───────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼──────┐ ┌────────▼──────┐ ┌───────▼──────┐
│   Personas   │ │   Workflows   │ │   Projects   │
│    (3001)    │ │    (3002)     │ │    (3003)    │
└──────────────┘ └───────────────┘ └──────────────┘
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │
              ┌───────────┼───────────┐
              │                       │
     ┌────────▼──────┐      ┌────────▼──────┐
     │    Context    │      │    Tokens     │
     │    (3004)     │      │    (3005)     │
     └───────────────┘      └───────────────┘
              │                       │
    ┌─────────┼───────────────────────┼─────────┐
    │         │         Storage       │         │
┌───▼──┐ ┌───▼──┐ ┌─────────┐ ┌──────▼──────┐ │
│Redis │ │Qdrant│ │PostgreSQL│ │   Claude    │ │
└──────┘ └──────┘ └──────────┘ │   Code      │ │
                                └─────────────┘ │
                                                │
```

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Claude Code installed locally
- 8GB+ RAM available
- Ports 3000-3005 available

### Starting the Platform

```bash
# Clone all repositories
./scripts/clone-all.sh

# Build all services
docker-compose build

# Start everything
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f

# Access the platform
open http://localhost:3000
```

### Stopping the Platform

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (full reset)
docker-compose down -v
```

## Service Configuration

### docker-compose.yml
```yaml
version: '3.8'

services:
  # API Gateway
  gateway:
    build: ../tcf-gateway
    image: tcf/gateway:latest
    container_name: tcf-gateway
    ports:
      - "3000:3000"
    environment:
      - TCF_PERSONAS_URL=http://personas:3001
      - TCF_WORKFLOWS_URL=http://workflows:3002
      - TCF_PROJECTS_URL=http://projects:3003
      - TCF_CONTEXT_URL=http://context:3004
      - TCF_TOKENS_URL=http://tokens:3005
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      - redis
      - personas
      - workflows
      - projects
      - context
      - tokens
    networks:
      - tcf-network

  # Personas Service
  personas:
    build: ../tcf-personas
    image: tcf/personas:latest
    container_name: tcf-personas
    ports:
      - "3001:3001"
    environment:
      - DATABASE_URL=postgresql://tcf:password@postgres:5432/tcf_personas
      - REDIS_URL=redis://redis:6379/1
      - TCF_CONTEXT_URL=http://context:3004
      - TCF_TOKENS_URL=http://tokens:3005
      - CLAUDE_HOME=/root/.claude
    volumes:
      - ~/.claude:/root/.claude:ro
      - persona-data:/app/data
    depends_on:
      - postgres
      - redis
    networks:
      - tcf-network

  # Workflows Service
  workflows:
    build: ../tcf-workflows
    image: tcf/workflows:latest
    container_name: tcf-workflows
    ports:
      - "3002:3002"
    environment:
      - DATABASE_URL=postgresql://tcf:password@postgres:5432/tcf_workflows
      - REDIS_URL=redis://redis:6379/2
      - TCF_PERSONAS_URL=http://personas:3001
      - TCF_CONTEXT_URL=http://context:3004
      - TCF_TOKENS_URL=http://tokens:3005
    volumes:
      - workflow-data:/app/data
    depends_on:
      - postgres
      - redis
    networks:
      - tcf-network

  # Projects Service
  projects:
    build: ../tcf-projects
    image: tcf/projects:latest
    container_name: tcf-projects
    ports:
      - "3003:3003"
    environment:
      - DATABASE_URL=postgresql://tcf:password@postgres:5432/tcf_projects
      - REDIS_URL=redis://redis:6379/3
      - TCF_CONTEXT_URL=http://context:3004
      - TCF_TOKENS_URL=http://tokens:3005
      - S3_BUCKET=tcf-artifacts
    volumes:
      - project-data:/app/data
    depends_on:
      - postgres
      - redis
    networks:
      - tcf-network

  # Context Service
  context:
    build: ../tcf-context
    image: tcf/context:latest
    container_name: tcf-context
    ports:
      - "3004:3004"
    environment:
      - DATABASE_URL=postgresql://tcf:password@postgres:5432/tcf_context
      - REDIS_URL=redis://redis:6379/4
      - QDRANT_URL=http://qdrant:6333
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    depends_on:
      - postgres
      - redis
      - qdrant
    networks:
      - tcf-network

  # Tokens Service
  tokens:
    build: ../tcf-tokens
    image: tcf/tokens:latest
    container_name: tcf-tokens
    ports:
      - "3005:3005"
    environment:
      - DATABASE_URL=postgresql://tcf:password@postgres:5432/tcf_tokens
      - REDIS_URL=redis://redis:6379/5
    depends_on:
      - postgres
      - redis
    networks:
      - tcf-network

  # Storage Services
  postgres:
    image: postgres:15-alpine
    container_name: tcf-postgres
    environment:
      - POSTGRES_USER=tcf
      - POSTGRES_PASSWORD=password
      - POSTGRES_MULTIPLE_DATABASES=tcf_personas,tcf_workflows,tcf_projects,tcf_context,tcf_tokens
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./scripts/init-postgres.sh:/docker-entrypoint-initdb.d/init.sh
    ports:
      - "5432:5432"
    networks:
      - tcf-network

  redis:
    image: redis:7-alpine
    container_name: tcf-redis
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data
    ports:
      - "6379:6379"
    networks:
      - tcf-network

  qdrant:
    image: qdrant/qdrant:latest
    container_name: tcf-qdrant
    ports:
      - "6333:6333"
    volumes:
      - qdrant-data:/qdrant/storage
    networks:
      - tcf-network

networks:
  tcf-network:
    driver: bridge

volumes:
  postgres-data:
  redis-data:
  qdrant-data:
  persona-data:
  workflow-data:
  project-data:
```

### docker-compose.override.yml (Development)
```yaml
version: '3.8'

services:
  gateway:
    build:
      context: ../tcf-gateway
      dockerfile: Dockerfile.dev
    volumes:
      - ../tcf-gateway:/app
    environment:
      - RACK_ENV=development

  personas:
    build:
      context: ../tcf-personas
      dockerfile: Dockerfile.dev
    volumes:
      - ../tcf-personas:/app
    environment:
      - RACK_ENV=development

  # Similar overrides for other services...
```

### docker-compose.prod.yml (Production)
```yaml
version: '3.8'

services:
  gateway:
    image: your-registry/tcf-gateway:${VERSION}
    restart: always
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: '1'
          memory: 512M
    environment:
      - RACK_ENV=production
      - JWT_SECRET=${JWT_SECRET}

  # Production configs for other services...

  # Add monitoring
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    networks:
      - tcf-network

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3006:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - ./monitoring/dashboards:/etc/grafana/provisioning/dashboards
    networks:
      - tcf-network
```

## Environment Configuration

### .env file
```bash
# API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Database
POSTGRES_USER=tcf
POSTGRES_PASSWORD=secure_password_here

# Redis
REDIS_PASSWORD=redis_password_here

# AWS (for artifact storage)
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
AWS_REGION=us-east-1

# Service Configuration
DEFAULT_DAILY_TOKEN_BUDGET=100000
MAX_CONTEXT_SIZE=200000

# Environment
ENVIRONMENT=development
VERSION=latest
```

## Scripts

### scripts/clone-all.sh
```bash
#!/bin/bash
# Clone all TCF repositories

REPOS=(
  tcf-gateway
  tcf-personas
  tcf-workflows
  tcf-projects
  tcf-context
  tcf-tokens
)

for repo in "${REPOS[@]}"; do
  if [ ! -d "../$repo" ]; then
    echo "Cloning $repo..."
    git clone https://github.com/yourusername/$repo.git ../$repo
  else
    echo "$repo already exists, pulling latest..."
    cd ../$repo && git pull && cd ../tcf-platform
  fi
done
```

### scripts/init-postgres.sh
```bash
#!/bin/bash
# Initialize multiple PostgreSQL databases

set -e

POSTGRES="psql --username ${POSTGRES_USER}"

echo "Creating databases..."

for DB in tcf_personas tcf_workflows tcf_projects tcf_context tcf_tokens; do
  echo "Creating database: $DB"
  $POSTGRES <<-EOSQL
    CREATE DATABASE $DB;
    GRANT ALL PRIVILEGES ON DATABASE $DB TO ${POSTGRES_USER};
EOSQL
done

echo "Databases created successfully!"
```

### scripts/health-check.sh
```bash
#!/bin/bash
# Check health of all services

SERVICES=(
  "gateway:3000"
  "personas:3001"
  "workflows:3002"
  "projects:3003"
  "context:3004"
  "tokens:3005"
)

echo "Checking TCF services health..."
echo "=============================="

for service in "${SERVICES[@]}"; do
  IFS=':' read -r name port <<< "$service"
  
  if curl -f -s "http://localhost:$port/health" > /dev/null; then
    echo "✅ $name (port $port) - Healthy"
  else
    echo "❌ $name (port $port) - Unhealthy or not running"
  fi
done

echo "=============================="
```

### scripts/backup.sh
```bash
#!/bin/bash
# Backup all TCF data

BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

echo "Backing up TCF platform..."

# Backup PostgreSQL
docker-compose exec -T postgres pg_dumpall -U tcf > "$BACKUP_DIR/postgres_backup.sql"

# Backup Redis
docker-compose exec -T redis redis-cli SAVE
docker cp tcf-redis:/data/dump.rdb "$BACKUP_DIR/redis_backup.rdb"

# Backup Qdrant
docker-compose exec -T qdrant tar -czf - /qdrant/storage | gzip > "$BACKUP_DIR/qdrant_backup.tar.gz"

echo "Backup completed to $BACKUP_DIR"
```

## API Documentation

### Postman Collection
A complete Postman collection is available at `./postman/TCF_Platform.postman_collection.json`

### Example Requests

#### Create and Run a Project
```bash
# 1. Create a new project
curl -X POST http://localhost:3000/projects \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Todo App",
    "vision": "I need a simple todo app with user authentication"
  }'

# 2. Run the factory
curl -X POST http://localhost:3000/factory/run \
  -H "Content-Type: application/json" \
  -d '{
    "project_id": "{{project_id}}",
    "workflow": "prototype_creation"
  }'

# 3. Check status
curl http://localhost:3000/factory/status/{{project_id}}
```

## Monitoring & Observability

### Health Endpoints
- Gateway: http://localhost:3000/health
- All services: http://localhost:3000/services/status

### Metrics
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3006

### Logs
```bash
# All logs
docker-compose logs -f

# Specific service
docker-compose logs -f gateway

# Last 100 lines
docker-compose logs --tail=100 personas
```

## Troubleshooting

### Common Issues

#### Services not connecting
```bash
# Check network
docker network ls
docker network inspect tcf-platform_tcf-network

# Restart networking
docker-compose down
docker-compose up -d
```

#### Database connection issues
```bash
# Check PostgreSQL
docker-compose exec postgres psql -U tcf -c "\l"

# Reset database
docker-compose down -v
docker-compose up -d
./scripts/migrate-all.sh
```

#### Claude Code integration issues
```bash
# Ensure ~/.claude is mounted
ls -la ~/.claude/agents/

# Check personas service can access Claude
docker-compose exec personas ls /root/.claude/agents/
```

## Development Workflow

### Running a Single Service
```bash
# Start only required dependencies
docker-compose up -d postgres redis

# Run service locally
cd ../tcf-gateway
bundle install
bundle exec rackup
```

### Testing
```bash
# Run all tests
./scripts/test-all.sh

# Test specific service
cd ../tcf-personas
bundle exec rspec
```

### Debugging
```bash
# Attach to running container
docker-compose exec gateway /bin/bash

# View real-time logs
docker-compose logs -f gateway

# Use debugger
# Add 'binding.pry' in code
docker-compose run --service-ports gateway
```

## Production Deployment

### Using Docker Swarm
```bash
docker stack deploy -c docker-compose.yml -c docker-compose.prod.yml tcf
```

### Using Kubernetes
```bash
kubectl apply -f k8s/
```

### Using AWS ECS
```bash
ecs-cli compose --file docker-compose.yml service up
```

## Security Considerations

1. **Change default passwords** in production
2. **Use secrets management** for API keys
3. **Enable TLS** for all services
4. **Implement rate limiting** at gateway
5. **Regular security updates** for all images
6. **Network isolation** between services
7. **Audit logging** for all operations

## Contributing

1. Fork the repository
2. Create feature branch
3. Make changes with tests
4. Submit pull request
5. Ensure CI passes

## License

TCF Platform is proprietary software. All rights reserved.

## Support

- Documentation: https://docs.tcf.example.com
- Issues: https://github.com/yourusername/tcf-platform/issues
- Discord: https://discord.gg/tcf
- Email: support@tcf.example.com
