# Branch Protection Rules Configuration

This document outlines the recommended branch protection rules for the TCF Platform repository to ensure code quality, security, and proper review processes.

## Repository Settings

### Default Branch
- **Main Branch:** `master`
- **Alternative:** `main` (if using GitHub's new default)

### General Settings
- **Allow merge commits:** ✅ Enabled
- **Allow squash merging:** ✅ Enabled  
- **Allow rebase merging:** ✅ Enabled
- **Automatically delete head branches:** ✅ Enabled

## Branch Protection Rules

### Master/Main Branch Protection

#### Basic Settings
```yaml
Branch: master
Require pull request reviews before merging: true
Required approving reviews: 1
Dismiss stale reviews when new commits are pushed: true
Require review from code owners: true
Restrict pushes to code owners: true
```

#### Status Check Requirements
```yaml
Require status checks to pass before merging: true
Require branches to be up to date before merging: true

Required Status Checks:
  - CI / Test Suite (ubuntu-latest, 3.2)
  - CI / Test Suite (ubuntu-latest, 3.3) 
  - CI / Test Suite (ubuntu-latest, 3.4)
  - CI / Code Quality
  - CI / Security Scan
  - CI / Docker Build Test
  - CI / Basic Integration Tests
  - CI / Quality Gate
  - Security Scanning / Security Report Generation
  - Docker Integration Testing / Docker Integration Report
```

#### Advanced Settings
```yaml
Restrict pushes that create files larger than 100MB: true
Restrict pushes to specific actors: false
Allow force pushes: false
Allow deletions: false
```

## Status Check Configuration

### Required Checks Explained

#### 1. Test Suite (Multiple Ruby Versions)
- **Purpose:** Ensure compatibility across Ruby 3.2, 3.3, and 3.4
- **Timeout:** 15 minutes
- **Failure Action:** Block merge
- **Requirements:**
  - All tests pass
  - Coverage ≥ 85%
  - No RSpec failures

#### 2. Code Quality (RuboCop)
- **Purpose:** Enforce code style and quality standards
- **Timeout:** 10 minutes
- **Failure Action:** Block merge
- **Requirements:**
  - Zero RuboCop violations
  - Consistent code formatting
  - Best practice compliance

#### 3. Security Scan
- **Purpose:** Detect security vulnerabilities and issues
- **Timeout:** 15 minutes
- **Failure Action:** Block merge on critical issues
- **Requirements:**
  - No critical security vulnerabilities
  - Bundler audit passes
  - Brakeman static analysis passes
  - No secrets detected

#### 4. Docker Build Test
- **Purpose:** Ensure Docker images build correctly
- **Timeout:** 10 minutes
- **Failure Action:** Block merge
- **Requirements:**
  - Docker image builds successfully
  - Container starts and responds to health checks
  - CLI functionality works in container

#### 5. Basic Integration Tests
- **Purpose:** Verify application works end-to-end
- **Timeout:** 10 minutes
- **Failure Action:** Block merge
- **Requirements:**
  - API endpoints respond correctly
  - Database connectivity works
  - Redis connectivity works

#### 6. Quality Gate
- **Purpose:** Overall quality assessment
- **Timeout:** 5 minutes
- **Failure Action:** Block merge
- **Requirements:**
  - All primary checks pass
  - Code coverage meets threshold
  - No critical issues detected

#### 7. Security Report Generation
- **Purpose:** Comprehensive security analysis
- **Timeout:** 20 minutes
- **Failure Action:** Block merge on critical findings
- **Requirements:**
  - No critical security vulnerabilities
  - Security report generated successfully
  - Risk assessment completed

#### 8. Docker Integration Report  
- **Purpose:** Verify Docker orchestration works
- **Timeout:** 30 minutes
- **Failure Action:** Block merge on critical failures
- **Requirements:**
  - Docker Compose orchestration works
  - Service connectivity verified
  - Container security scan passes

## Code Review Requirements

### Required Reviewers
- **Minimum:** 1 approving review
- **Code Owners:** Required for certain paths
- **Stale Review Dismissal:** Enabled

### Code Owner Paths
```gitignore
# Core application files
/lib/                    @tcf-platform/core-team
/bin/                    @tcf-platform/core-team
/app.rb                  @tcf-platform/core-team
/config.ru               @tcf-platform/core-team

# CI/CD and infrastructure
/.github/workflows/      @tcf-platform/devops-team
/Dockerfile*             @tcf-platform/devops-team
/docker-compose*.yml     @tcf-platform/devops-team

# Security-sensitive files
/lib/jwt_*              @tcf-platform/security-team
/lib/*auth*             @tcf-platform/security-team
/lib/environment*       @tcf-platform/security-team

# Documentation
/README.md              @tcf-platform/docs-team
/docs/                  @tcf-platform/docs-team
/CLAUDE.md              @tcf-platform/docs-team

# Configuration
/Gemfile                @tcf-platform/core-team
/.rubocop.yml           @tcf-platform/core-team
/.env.example           @tcf-platform/core-team
```

## Exception Handling

### Emergency Hotfix Process
For critical production issues, a streamlined process is available:

1. **Create hotfix branch** from `master`
2. **Apply minimal fix** (single purpose)
3. **Fast-track review** (1 approver, expedited checks)
4. **Deploy immediately** after merge
5. **Follow up** with comprehensive fix in regular PR

### Hotfix Branch Protection
```yaml
Branch Pattern: hotfix/*
Require pull request reviews: true
Required approving reviews: 1
Dismiss stale reviews: false
Required Status Checks:
  - CI / Test Suite (ubuntu-latest, 3.4)  # Single version for speed
  - CI / Code Quality
  - CI / Security Scan
Allow administrators to bypass: true
```

## Bypass Permissions

### Who Can Bypass Branch Protection
- **Repository Administrators:** Only in emergency situations
- **Security Team:** For security-critical fixes
- **DevOps Team:** For infrastructure emergencies

### Bypass Audit
All bypasses are:
- **Logged** in GitHub audit trail
- **Reported** to team leads
- **Reviewed** in weekly security meetings
- **Documented** with justification

## Monitoring and Alerting

### PR Status Monitoring
```yaml
Alerts for:
  - PRs open > 48 hours
  - Failed status checks > 3 times
  - Security scan failures
  - Coverage drops below 85%
  - Long-running CI jobs (>30 minutes)
```

### Weekly Reports
- **PR Metrics:** Average time to merge, review counts
- **Quality Trends:** Test coverage, security findings
- **Process Health:** Bypass usage, failed checks
- **Team Performance:** Review response times

## Configuration Commands

### GitHub CLI Commands
```bash
# Set up branch protection for master
gh api repos/:owner/:repo/branches/master/protection \
  --method PUT \
  --input branch-protection.json

# Example protection JSON
cat > branch-protection.json << EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "CI / Test Suite (ubuntu-latest, 3.2)",
      "CI / Test Suite (ubuntu-latest, 3.3)", 
      "CI / Test Suite (ubuntu-latest, 3.4)",
      "CI / Code Quality",
      "CI / Security Scan",
      "CI / Docker Build Test",
      "CI / Basic Integration Tests",
      "CI / Quality Gate"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "restrict_pushes": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

### Validation Script
```bash
#!/bin/bash
# validate-branch-protection.sh

echo "🔒 Validating branch protection settings..."

# Check if protection is enabled
PROTECTION=$(gh api repos/:owner/:repo/branches/master/protection 2>/dev/null || echo "null")

if [ "$PROTECTION" = "null" ]; then
  echo "❌ Branch protection not configured"
  exit 1
fi

# Check required status checks
CHECKS=$(echo "$PROTECTION" | jq -r '.required_status_checks.contexts[]' 2>/dev/null || echo "")

REQUIRED_CHECKS=(
  "CI / Test Suite"
  "CI / Code Quality" 
  "CI / Security Scan"
  "CI / Quality Gate"
)

for check in "${REQUIRED_CHECKS[@]}"; do
  if echo "$CHECKS" | grep -q "$check"; then
    echo "✅ $check - configured"
  else
    echo "❌ $check - missing"
    exit 1
  fi
done

echo "✅ Branch protection is properly configured"
```

## Implementation Checklist

### Initial Setup
- [ ] Configure master branch protection
- [ ] Set up code owners file
- [ ] Define required status checks
- [ ] Configure review requirements
- [ ] Set up bypass permissions

### Team Onboarding
- [ ] Document process in team wiki
- [ ] Train team on PR workflow
- [ ] Set up notification channels
- [ ] Create escalation procedures
- [ ] Schedule regular reviews

### Monitoring Setup
- [ ] Configure PR analytics
- [ ] Set up quality dashboards
- [ ] Create alert channels
- [ ] Define SLAs for reviews
- [ ] Establish metrics tracking

## Troubleshooting

### Common Issues

#### Status Check Not Running
```bash
# Check workflow file syntax
gh workflow list
gh workflow view ci.yml

# Validate required contexts match workflow jobs
grep "name:" .github/workflows/*.yml
```

#### PR Cannot Be Merged
```bash
# Check specific failing checks
gh pr checks <pr-number>

# View detailed status
gh pr view <pr-number> --json statusCheckRollup
```

#### Review Requirements Not Met
```bash
# Check code owners
cat .github/CODEOWNERS

# Verify review permissions
gh api repos/:owner/:repo/collaborators
```

### Support Contacts
- **CI/CD Issues:** @tcf-platform/devops-team
- **Security Questions:** @tcf-platform/security-team  
- **Process Issues:** @tcf-platform/core-team
- **Emergency Bypass:** Repository administrators

## References
- [GitHub Branch Protection Documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)
- [TCF Platform Contribution Guidelines](../CONTRIBUTING.md)
- [Security Review Process](../docs/security-review-process.md)
- [Emergency Response Procedures](../docs/emergency-response.md)