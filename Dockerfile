# Use Ruby 3.3 slim image for production
FROM ruby:3.3-slim

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    curl \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 \
    && bundle install --without development test

# Copy application code
COPY . .

# Create non-root user
RUN groupadd -r tcf && useradd -r -g tcf tcf
RUN chown -R tcf:tcf /app
USER tcf

# Expose port
EXPOSE 3006

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3006/health || exit 1

# Start the application
CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "3006"]