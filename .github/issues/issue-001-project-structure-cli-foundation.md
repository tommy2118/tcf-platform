# Issue #1: Project Structure & CLI Foundation

**Label:** `phase:foundation`, `priority:p1`, `type:foundation`  
**Branch:** `feature/issue-1-project-structure-cli-foundation`  
**Dependencies:** None (requires fresh master)

## Context Budget
- **Estimated tokens:** 15,000-20,000
- **Estimated files:** 15-20 files
- **Complexity:** Medium (Ruby/Sinatra setup with CLI interface)
- **Test coverage target:** 85%+

## Problem Statement
TCF Platform currently exists only as documentation in CLAUDE.md. We need to establish the foundational Ruby/Sinatra application structure with a CLI interface that can coordinate Docker services, following the proven architecture patterns from TCF Gateway.

## Objectives
Create a production-ready Ruby/Sinatra application foundation that serves as both a CLI tool and web API for orchestrating TCF microservices, with comprehensive testing and CI/CD pipeline.

## TDD-Ready Acceptance Criteria

### Phase 1: Red - Basic Structure Tests
- [ ] **Test: CLI entry point** - `bin/tcf-platform --version` returns version
- [ ] **Test: Sinatra app loads** - Basic health endpoint responds with 200
- [ ] **Test: Configuration loading** - Environment variables are properly loaded and validated
- [ ] **Test: Logging system** - Structured logging outputs to stdout/file
- [ ] **Test: Error handling** - CLI shows helpful errors for invalid commands

### Phase 2: Green - Implementation
- [ ] **File: Gemfile** - Dependencies including sinatra, thor, dotenv, faraday
- [ ] **File: bin/tcf-platform** - Executable CLI entry point using Thor
- [ ] **File: app.rb** - Main Sinatra application with health endpoint
- [ ] **File: config.ru** - Rack configuration for web server
- [ ] **File: lib/tcf_platform/cli.rb** - CLI command structure
- [ ] **File: lib/tcf_platform/config.rb** - Configuration management
- [ ] **File: lib/tcf_platform/logger.rb** - Structured logging
- [ ] **File: lib/environment_validator.rb** - Environment validation (from Gateway)

### Phase 3: Refactor - Quality & Integration
- [ ] **CI Pipeline** - GitHub Actions with Ruby 3.2+, RSpec, RuboCop
- [ ] **Security** - Brakeman, bundler-audit integration
- [ ] **Documentation** - README with CLI usage examples
- [ ] **Docker** - Dockerfile and development compose file
- [ ] **Test Coverage** - SimpleCov reporting 85%+ coverage

## File Structure to Create
```
tcf-platform/
├── bin/
│   └── tcf-platform                    # CLI executable
├── lib/
│   ├── tcf_platform/
│   │   ├── cli.rb                      # Thor-based CLI
│   │   ├── config.rb                   # Configuration management
│   │   ├── logger.rb                   # Structured logging
│   │   └── version.rb                  # Version constant
│   └── environment_validator.rb        # From Gateway pattern
├── spec/
│   ├── spec_helper.rb                  # RSpec configuration
│   ├── cli_spec.rb                     # CLI command tests
│   ├── app_spec.rb                     # Sinatra app tests
│   ├── config_spec.rb                  # Configuration tests
│   └── support/                        # Test helpers
├── .github/workflows/
│   ├── ci.yml                          # Main CI pipeline
│   └── security.yml                    # Security scanning
├── app.rb                              # Main Sinatra app
├── config.ru                           # Rack config
├── Gemfile                             # Dependencies
├── .env.example                        # Environment template
├── .rubocop.yml                        # Linting rules
├── Dockerfile                          # Container build
└── docker-compose.dev.yml              # Development environment
```

## Implementation Guidelines

### CLI Architecture (Thor-based)
```ruby
class TcfPlatform::CLI < Thor
  desc "version", "Show version"
  def version
    puts TcfPlatform::VERSION
  end

  desc "health", "Check platform health"
  def health
    # Health check logic
  end

  desc "start", "Start all services"
  def start
    # Service startup logic
  end
end
```

### Sinatra App Structure
```ruby
# app.rb
require 'sinatra'
require 'sinatra/json'
require_relative 'lib/tcf_platform/config'
require_relative 'lib/environment_validator'

class TcfPlatformApp < Sinatra::Base
  configure do
    enable :logging
    set :environment, :production if ENV['RACK_ENV'] == 'production'
  end

  get '/health' do
    json status: 'healthy', timestamp: Time.now.iso8601
  end
end
```

### Configuration Pattern (from Gateway)
```ruby
module TcfPlatform
  class Config
    REQUIRED_ENV = %w[].freeze
    OPTIONAL_ENV = {
      'PORT' => '3000',
      'LOG_LEVEL' => 'info'
    }.freeze

    def self.load!
      validate_environment!
      new
    end

    private

    def self.validate_environment!
      EnvironmentValidator.validate!(REQUIRED_ENV, OPTIONAL_ENV)
    end
  end
end
```

## Definition of Done
- [ ] CLI tool installed and functional (`gem install` or local)
- [ ] Web API responds to health checks
- [ ] All tests pass with 85%+ coverage
- [ ] RuboCop passes with Gateway-level configuration
- [ ] Security scans (Brakeman, bundler-audit) pass
- [ ] CI/CD pipeline green
- [ ] README documents CLI usage and API endpoints
- [ ] Docker container builds and runs
- [ ] Environment validation follows Gateway patterns

## Integration Points
- **Next Issue (#2):** Docker Compose service management will extend the CLI commands
- **Gateway Reference:** Use lib/environment_validator.rb pattern
- **Testing:** Follow Gateway's comprehensive spec structure

## Context Notes
- This establishes the foundation that all subsequent issues will build upon
- CLI provides human interface, API provides programmatic interface  
- Architecture mirrors Gateway for consistency and maintainability
- Focus on production-ready patterns from the start