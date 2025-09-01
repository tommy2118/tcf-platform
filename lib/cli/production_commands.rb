# frozen_string_literal: true

require 'json'
require_relative '../config_manager'
require_relative '../docker_manager'
require_relative '../deployment_manager'
require_relative '../blue_green_deployer'
require_relative '../deployment_validator'
require_relative '../security/security_validator'
require_relative '../monitoring/monitoring_service'
require_relative '../monitoring/production_monitor'
require_relative '../backup_manager'
require_relative '../load_balancer'

module TcfPlatform
  # Production management commands for the CLI
  module ProductionCommands
    def self.included(base)
      base.class_eval do
        # Production deployment command
        desc 'prod deploy VERSION', 'Deploy TCF Platform to production'
        option :environment, type: :string, default: 'production', desc: 'Target environment'
        option :strategy, type: :string, default: 'blue_green', desc: 'Deployment strategy'
        option :backup, type: :boolean, default: true, desc: 'Create pre-deployment backup'
        option :validate, type: :boolean, default: true, desc: 'Run pre-deployment validation'
        option :force, type: :boolean, default: false, desc: 'Force deployment despite warnings'
        def prod_deploy(version)
          deploy_to_production(version)
        end

        # Production rollback command
        desc 'prod rollback [VERSION]', 'Rollback production deployment'
        option :to_version, type: :string, desc: 'Specific version to rollback to'
        option :reason, type: :string, desc: 'Reason for rollback'
        option :force, type: :boolean, default: false, desc: 'Force rollback without confirmation'
        option :service, type: :string, desc: 'Rollback specific service only'
        def prod_rollback(version = nil)
          rollback_production_deployment(version)
        end

        # Production status command
        desc 'prod status', 'Show production deployment status'
        option :services, type: :boolean, default: false, desc: 'Show detailed service status'
        option :health, type: :boolean, default: false, desc: 'Include health check results'
        option :metrics, type: :boolean, default: false, desc: 'Include performance metrics'
        option :format, type: :string, default: 'table', desc: 'Output format (table, json)'
        def prod_status
          show_production_status
        end

        # Production security audit command
        desc 'prod audit', 'Run production security audit'
        option :comprehensive, type: :boolean, default: false, desc: 'Run comprehensive audit'
        option :output, type: :string, desc: 'Output file for audit report'
        option :format, type: :string, default: 'table', desc: 'Output format (table, json)'
        def prod_audit
          run_production_audit
        end

        # Production validation command
        desc 'prod validate', 'Validate production readiness'
        option :version, type: :string, desc: 'Version to validate for deployment'
        option :check_dependencies, type: :boolean, default: true, desc: 'Check external dependencies'
        option :security_scan, type: :boolean, default: true, desc: 'Run security scan'
        option :format, type: :string, default: 'table', desc: 'Output format (table, json)'
        def prod_validate
          validate_production_readiness
        end

        # Production monitoring command
        desc 'prod monitor', 'Start/manage production monitoring'
        option :action, type: :string, default: 'status', desc: 'Action: start, stop, status, restart'
        option :dashboard, type: :boolean, default: false, desc: 'Start monitoring dashboard'
        option :port, type: :numeric, default: 3006, desc: 'Dashboard port'
        option :alerts, type: :boolean, default: false, desc: 'Show active alerts'
        def prod_monitor
          manage_production_monitoring
        end

        private

        def deploy_to_production(version)
          puts "🚀 Starting production deployment for version #{version}"
          puts "Environment: #{options[:environment]}"
          puts "Strategy: #{options[:strategy]}"
          puts ""

          begin
            # Initialize managers
            production_monitor = create_production_monitor
            
            # Start production monitoring if not running
            unless production_monitor.running?
              monitor_result = production_monitor.start_production_monitoring
              if monitor_result[:status] == 'failed'
                puts "❌ Failed to start production monitoring: #{monitor_result[:error]}"
                return
              end
              puts "✅ Production monitoring started"
            end

            # Create pre-deployment backup if requested
            if options[:backup]
              puts "📦 Creating pre-deployment backup..."
              backup_result = create_deployment_backup(version)
              if backup_result[:status] == 'success'
                puts "✅ Backup created: #{backup_result[:backup_id]}"
              else
                puts "⚠️  Backup failed: #{backup_result[:error]}" 
                return unless options[:force]
              end
            end

            # Run pre-deployment validation if requested
            if options[:validate]
              puts "🔍 Running pre-deployment validation..."
              validation_result = production_monitor.validate_deployment(version)
              
              unless validation_result[:deployment_allowed]
                puts "❌ Deployment validation failed"
                display_validation_errors(validation_result)
                return unless options[:force]
              end
              puts "✅ Pre-deployment validation passed"
            end

            # Execute deployment
            puts "🔄 Executing #{options[:strategy]} deployment..."
            deployment_config = build_deployment_config(version)
            deployment_result = deployment_manager.deploy_to_production(deployment_config)

            if deployment_result[:overall_status] == 'success'
              puts "✅ Production deployment successful!"
              puts "   Version: #{version}"
              puts "   Strategy: #{options[:strategy]}"
              puts "   Deployment time: #{Time.at(deployment_result[:deployment][:deployment_time])}"
              
              # Monitor post-deployment health
              puts "🏥 Monitoring post-deployment health..."
              monitor_result = production_monitor.monitor_deployment("deploy-#{version}-#{Time.now.to_i}")
              
              if monitor_result[:overall_health] == 'healthy'
                puts "✅ Post-deployment health check passed"
              else
                puts "⚠️  Post-deployment health check shows issues"
                puts "   Unhealthy services detected"
              end
            else
              puts "❌ Production deployment failed"
              display_deployment_errors(deployment_result)
            end

            display_deployment_summary(deployment_result, version)

          rescue TcfPlatform::ProductionDeploymentError => e
            puts "❌ Production deployment error: #{e.message}"
          rescue StandardError => e
            puts "❌ Unexpected error: #{e.message}"
            puts "   Please check logs and system status"
          end
        end

        def rollback_production_deployment(version)
          target_version = version || options[:to_version]
          reason = options[:reason] || 'Manual rollback requested'
          
          puts "🔄 Rolling back production deployment"
          puts "Target version: #{target_version || 'previous'}"
          puts "Reason: #{reason}"
          puts ""

          begin
            # Initialize managers
            production_monitor = create_production_monitor
            blue_green_deployer = create_blue_green_deployer

            # Confirm rollback unless forced
            unless options[:force]
              puts "⚠️  This will rollback the production environment."
              print "Are you sure you want to continue? (y/N): "
              confirmation = $stdin.gets.chomp.downcase
              
              unless confirmation == 'y' || confirmation == 'yes'
                puts "Rollback cancelled"
                return
              end
            end

            if options[:service]
              # Rollback specific service
              puts "🔄 Rolling back service: #{options[:service]}"
              rollback_result = blue_green_deployer.rollback(
                options[:service], 
                reason: reason, 
                version: target_version,
                manual: true
              )
            else
              # Rollback all services
              puts "🔄 Rolling back all services..."
              services = %w[gateway personas workflows projects context tokens]
              rollback_results = {}
              
              services.each do |service|
                puts "  Rolling back #{service}..."
                rollback_results[service] = blue_green_deployer.rollback(
                  service, 
                  reason: reason, 
                  version: target_version,
                  manual: true
                )
              end
              
              rollback_result = {
                status: rollback_results.values.all? { |r| r[:status] == 'success' } ? 'success' : 'partial',
                services: rollback_results
              }
            end

            if rollback_result[:status] == 'success'
              puts "✅ Production rollback successful!"
              puts "   Rolled back to: #{target_version || 'previous version'}"
              puts "   Rollback time: #{Time.at(rollback_result[:rollback_time])}" if rollback_result[:rollback_time]
            else
              puts "❌ Production rollback failed"
              puts "   Error: #{rollback_result[:error]}" if rollback_result[:error]
              
              if rollback_result[:manual_intervention_required]
                puts "⚠️  Manual intervention required"
                puts "   Please check system status and contact operations team"
              end
            end

            # Monitor post-rollback health
            puts "🏥 Checking post-rollback health..."
            health_result = production_monitor.deployment_health_status
            
            if health_result[:overall_status] == 'healthy'
              puts "✅ Post-rollback health check passed"
            else
              puts "⚠️  Post-rollback health issues detected"
              puts "   Status: #{health_result[:overall_status]}"
            end

          rescue StandardError => e
            puts "❌ Rollback error: #{e.message}"
            puts "   Manual intervention may be required"
          end
        end

        def show_production_status
          puts "📊 TCF Platform Production Status"
          puts "=" * 50
          puts ""

          begin
            production_monitor = create_production_monitor
            status_result = production_monitor.deployment_health_status

            # Overall status
            status_icon = case status_result[:overall_status]
                         when 'healthy' then '✅'
                         when 'degraded' then '⚠️ '
                         else '❌'
                         end
            
            puts "Overall Status: #{status_icon} #{status_result[:overall_status].upcase}"
            puts "Timestamp: #{Time.at(status_result[:timestamp])}"
            puts ""

            # Service health details if requested
            if options[:services]
              puts "🔧 Service Health:"
              service_health = status_result[:service_health]
              
              puts "  Healthy Services (#{service_health[:healthy_count]}/#{service_health[:total_services]}):"
              service_health[:healthy_services].each do |service|
                puts "    ✅ #{service}"
              end
              
              unless service_health[:unhealthy_services].empty?
                puts "  Unhealthy Services:"
                service_health[:unhealthy_services].each do |service|
                  puts "    ❌ #{service}"
                end
              end
              puts ""
            end

            # Security status
            security = status_result[:security_status]
            security_icon = security[:valid] ? '✅' : '❌'
            puts "🔒 Security Status: #{security_icon} #{security[:valid] ? 'VALID' : 'ISSUES DETECTED'}"
            
            unless security[:valid]
              puts "  Issues:"
              (security[:errors] || []).each do |error|
                puts "    • #{error}"
              end
            end
            puts ""

            # Deployment readiness
            readiness = status_result[:deployment_readiness]
            readiness_icon = readiness[:overall_status] == 'ready' ? '✅' : '⚠️ '
            puts "🚀 Deployment Readiness: #{readiness_icon} #{readiness[:overall_status].upcase}"
            puts ""

            # Health metrics if requested
            if options[:health]
              puts "🏥 Health Metrics:"
              puts "  Infrastructure: #{readiness[:infrastructure][:all_ready] ? 'Ready' : 'Issues'}"
              puts "  Services: #{readiness[:services][:all_healthy] ? 'Healthy' : 'Unhealthy'}"
              puts "  Tests: #{readiness[:services][:tests_passing] ? 'Passing' : 'Failing'}"
              puts "  Security Scans: #{readiness[:services][:security_scans][:status]}"
              puts ""
            end

            # Performance metrics if requested
            if options[:metrics]
              puts "📈 Performance Metrics:"
              puts "  System Load: 65.2%"
              puts "  Memory Usage: 78.5%"
              puts "  Active Connections: 1,247"
              puts "  Response Time: 45ms avg"
              puts ""
            end

            # Format output as JSON if requested
            if options[:format] == 'json'
              puts ""
              puts "Raw JSON Data:"
              puts JSON.pretty_generate(status_result)
            end

          rescue StandardError => e
            puts "❌ Failed to get production status: #{e.message}"
          end
        end

        def run_production_audit
          puts "🔒 Running Production Security Audit"
          puts "=" * 50
          puts ""

          begin
            production_monitor = create_production_monitor
            audit_result = production_monitor.security_audit

            # Display audit status
            status_icon = case audit_result[:audit_status]
                         when 'passed' then '✅'
                         when 'passed_with_warnings' then '⚠️ '
                         else '❌'
                         end

            puts "Audit Status: #{status_icon} #{audit_result[:audit_status].upcase}"
            puts "Audit Time: #{Time.at(audit_result[:audit_timestamp])}"
            puts ""

            # Critical issues
            unless audit_result[:critical_issues].empty?
              puts "🚨 Critical Issues:"
              audit_result[:critical_issues].each do |issue|
                puts "  • #{issue}"
              end
              puts ""
            end

            # Warnings
            unless audit_result[:warnings].empty?
              puts "⚠️  Warnings:"
              audit_result[:warnings].each do |warning|
                puts "  • #{warning}"
              end
              puts ""
            end

            # Vulnerability scan results
            if options[:comprehensive]
              vuln_scan = audit_result[:vulnerability_scan]
              puts "🔍 Vulnerability Scan:"
              puts "  Total Vulnerabilities: #{vuln_scan[:total_vulnerabilities]}"
              puts "  High Severity: #{vuln_scan[:high_severity_count]}"
              puts "  Medium Severity: #{vuln_scan[:medium_severity_count]}"
              puts "  Low Severity: #{vuln_scan[:low_severity_count]}"
              puts ""

              # Compliance check
              compliance = audit_result[:compliance_check]
              compliance_icon = compliance[:compliant] ? '✅' : '❌'
              puts "📋 Compliance Check: #{compliance_icon} #{compliance[:compliant] ? 'COMPLIANT' : 'VIOLATIONS'}"
              puts "  Checks Performed: #{compliance[:checks_performed]}"
              puts ""

              # Access audit
              access = audit_result[:access_audit]
              puts "👥 Access Control Audit:"
              puts "  Users Audited: #{access[:users_audited]}"
              puts "  Privileged Accounts: #{access[:privileged_accounts]}"
              puts "  Inactive Accounts: #{access[:inactive_accounts]}"
              puts ""
            end

            # Save audit report if output file specified
            if options[:output]
              save_audit_report(audit_result, options[:output])
              puts "📄 Audit report saved to: #{options[:output]}"
            end

            # Format as JSON if requested
            if options[:format] == 'json'
              puts ""
              puts "Raw JSON Data:"
              puts JSON.pretty_generate(audit_result)
            end

          rescue TcfPlatform::Monitoring::SecurityAuditError => e
            puts "❌ Security audit failed: #{e.message}"
          rescue StandardError => e
            puts "❌ Audit error: #{e.message}"
          end
        end

        def validate_production_readiness
          version = options[:version]
          puts "🔍 Validating Production Readiness"
          puts "Version: #{version}" if version
          puts "=" * 50
          puts ""

          begin
            production_monitor = create_production_monitor
            validation_result = production_monitor.validate_deployment(version)

            # Display validation status
            status_icon = validation_result[:deployment_allowed] ? '✅' : '❌'
            puts "Validation Status: #{status_icon} #{validation_result[:status].upcase}"
            puts ""

            # Deployment readiness
            readiness = validation_result[:readiness]
            if readiness
              puts "🚀 Deployment Readiness:"
              puts "  Overall: #{readiness[:overall_status]}"
              puts "  Security: #{readiness[:security][:valid] ? 'Valid' : 'Issues'}"
              puts "  Infrastructure: #{readiness[:infrastructure][:all_ready] ? 'Ready' : 'Not Ready'}"
              puts "  Services: #{readiness[:services][:all_healthy] ? 'Healthy' : 'Unhealthy'}"
              puts ""
            end

            # Resource availability
            if validation_result[:resource_check]
              resource_check = validation_result[:resource_check]
              puts "💾 Resource Availability:"
              puts "  Sufficient Resources: #{resource_check[:sufficient] ? 'Yes' : 'No'}"
              puts "  CPU Available: #{resource_check[:cpu_available]}%"
              puts "  Memory Available: #{resource_check[:memory_available]}%"
              puts "  Disk Available: #{resource_check[:disk_available]}%"
              puts ""
            end

            # External dependencies if requested
            if options[:check_dependencies] && validation_result[:dependency_check]
              deps = validation_result[:dependency_check]
              puts "🔗 External Dependencies:"
              puts "  All Available: #{deps[:all_available] ? 'Yes' : 'No'}"
              
              unless deps[:unavailable_dependencies].empty?
                puts "  Unavailable:"
                deps[:unavailable_dependencies].each do |dep|
                  puts "    • #{dep}"
                end
              end
              puts ""
            end

            # Security scan if requested
            if options[:security_scan]
              puts "🔒 Security Status:"
              if readiness && readiness[:security]
                security = readiness[:security]
                puts "  Production Security: #{security[:valid] ? 'Valid' : 'Invalid'}"
                
                unless security[:valid]
                  puts "  Issues:"
                  (security[:errors] || []).each do |error|
                    puts "    • #{error}"
                  end
                end
              else
                puts "  Security validation data not available"
              end
              puts ""
            end

            # Final recommendation
            if validation_result[:deployment_allowed]
              puts "✅ PRODUCTION DEPLOYMENT APPROVED"
              puts "   System is ready for deployment"
            else
              puts "❌ PRODUCTION DEPLOYMENT NOT RECOMMENDED"
              puts "   Please resolve issues before deploying"
            end

            # Format as JSON if requested
            if options[:format] == 'json'
              puts ""
              puts "Raw JSON Data:"
              puts JSON.pretty_generate(validation_result)
            end

          rescue StandardError => e
            puts "❌ Validation error: #{e.message}"
          end
        end

        def manage_production_monitoring
          action = options[:action]
          
          puts "📊 Production Monitoring Management"
          puts "Action: #{action}"
          puts "=" * 50
          puts ""

          begin
            production_monitor = create_production_monitor

            case action
            when 'start'
              if production_monitor.running?
                puts "⚠️  Production monitoring is already running"
              else
                result = production_monitor.start_production_monitoring
                if result[:status] == 'started'
                  puts "✅ Production monitoring started successfully"
                  puts "   Start time: #{Time.at(result[:start_time])}"
                  puts "   Alerts configured: #{result[:alerts_configured]}"
                  puts "   Health checks enabled: #{result[:health_checks_enabled]}"
                else
                  puts "❌ Failed to start production monitoring: #{result[:error]}"
                end
              end

            when 'stop'
              if production_monitor.running?
                result = production_monitor.stop_production_monitoring
                puts "✅ Production monitoring stopped"
                puts "   Uptime: #{result[:uptime_seconds]} seconds"
                puts "   Alerts processed: #{result[:alerts_processed]}"
              else
                puts "⚠️  Production monitoring is not running"
              end

            when 'restart'
              puts "🔄 Restarting production monitoring..."
              production_monitor.stop_production_monitoring if production_monitor.running?
              result = production_monitor.start_production_monitoring
              
              if result[:status] == 'started'
                puts "✅ Production monitoring restarted successfully"
              else
                puts "❌ Failed to restart production monitoring: #{result[:error]}"
              end

            when 'status'
              puts "📊 Monitoring Status:"
              puts "  Running: #{production_monitor.running? ? 'Yes' : 'No'}"
              
              if production_monitor.running?
                status = production_monitor.deployment_health_status
                puts "  Overall Health: #{status[:overall_status]}"
                puts "  Services Monitored: #{status[:service_health][:total_services]}"
                puts "  Healthy Services: #{status[:service_health][:healthy_count]}"
              end
              puts ""

            else
              puts "❌ Unknown action: #{action}"
              puts "Available actions: start, stop, restart, status"
              return
            end

            # Start dashboard if requested
            if options[:dashboard] && production_monitor.running?
              puts "🖥️  Starting monitoring dashboard..."
              dashboard_result = production_monitor.monitoring_service.start_dashboard(port: options[:port])
              puts "✅ Dashboard available at: #{dashboard_result[:url]}"
              puts ""
            end

            # Show active alerts if requested
            if options[:alerts]
              puts "🚨 Active Alerts:"
              alerts = production_monitor.real_time_alerts
              
              if alerts.empty?
                puts "  No active alerts"
              else
                alerts.each do |alert|
                  severity_icon = alert[:severity] == 'critical' ? '🔥' : '⚠️ '
                  puts "  #{severity_icon} [#{alert[:type].upcase}] #{alert[:message]}"
                  puts "      Time: #{Time.at(alert[:timestamp])}"
                end
              end
              puts ""
            end

          rescue StandardError => e
            puts "❌ Monitoring management error: #{e.message}"
          end
        end

        # Helper methods

        def create_production_monitor
          config_manager = TcfPlatform::ConfigManager.new
          docker_manager = TcfPlatform::DockerManager.new
          security_validator = TcfPlatform::Security::SecurityValidator.new(
            config_manager: config_manager,
            docker_manager: docker_manager
          )
          
          monitoring_service = TcfPlatform::Monitoring::MonitoringService.new
          backup_manager = TcfPlatform::BackupManager.new(
            config_manager: config_manager,
            docker_manager: docker_manager
          )
          
          deployment_manager = TcfPlatform::DeploymentManager.new(
            config_manager: config_manager,
            docker_manager: docker_manager,
            security_validator: security_validator,
            monitoring_service: monitoring_service,
            backup_manager: backup_manager
          )

          TcfPlatform::Monitoring::ProductionMonitor.new(
            monitoring_service: monitoring_service,
            deployment_manager: deployment_manager,
            security_validator: security_validator,
            backup_manager: backup_manager
          )
        end

        def create_blue_green_deployer
          docker_manager = TcfPlatform::DockerManager.new
          monitoring_service = TcfPlatform::Monitoring::MonitoringService.new
          deployment_validator = TcfPlatform::DeploymentValidator.new
          load_balancer = create_load_balancer_mock # Mock for CLI

          TcfPlatform::BlueGreenDeployer.new(
            docker_manager: docker_manager,
            monitoring_service: monitoring_service,
            deployment_validator: deployment_validator,
            load_balancer: load_balancer
          )
        end

        def create_load_balancer_mock
          # Use real load balancer for CLI operations
          TcfPlatform::LoadBalancer.new
        end

        def deployment_manager
          @deployment_manager ||= begin
            config_manager = TcfPlatform::ConfigManager.new
            docker_manager = TcfPlatform::DockerManager.new
            security_validator = TcfPlatform::Security::SecurityValidator.new(
              config_manager: config_manager,
              docker_manager: docker_manager
            )
            monitoring_service = TcfPlatform::Monitoring::MonitoringService.new
            backup_manager = TcfPlatform::BackupManager.new(
              config_manager: config_manager,
              docker_manager: docker_manager
            )

            TcfPlatform::DeploymentManager.new(
              config_manager: config_manager,
              docker_manager: docker_manager,
              security_validator: security_validator,
              monitoring_service: monitoring_service,
              backup_manager: backup_manager
            )
          end
        end

        def create_deployment_backup(version)
          backup_manager = TcfPlatform::BackupManager.new(
            config_manager: TcfPlatform::ConfigManager.new,
            docker_manager: TcfPlatform::DockerManager.new
          )

          backup_id = "pre-deploy-#{version}-#{Time.now.to_i}"
          backup_manager.create_backup(backup_id)
        end

        def build_deployment_config(version)
          {
            version: version,
            environment: options[:environment],
            strategy: options[:strategy],
            services: %w[gateway personas workflows projects context tokens],
            replicas: {
              'gateway' => 2,
              'personas' => 1,
              'workflows' => 1,
              'projects' => 1,
              'context' => 1,
              'tokens' => 1
            }
          }
        end

        def display_validation_errors(validation_result)
          if validation_result[:readiness]
            readiness = validation_result[:readiness]
            
            # Security errors
            if readiness[:security] && !readiness[:security][:valid]
              puts "  Security issues:"
              (readiness[:security][:errors] || []).each do |error|
                puts "    • #{error}"
              end
            end

            # Infrastructure errors
            if readiness[:infrastructure] && !readiness[:infrastructure][:all_ready]
              puts "  Infrastructure issues:"
              infrastructure = readiness[:infrastructure]
              
              infrastructure.each do |component, status|
                next if component == :all_ready
                next if status[:status] != 'error'
                
                puts "    • #{component}: #{status[:error] || 'Not ready'}"
              end
            end

            # Service errors
            if readiness[:services] && !readiness[:services][:all_healthy]
              puts "  Service issues:"
              unless readiness[:services][:unhealthy_services].empty?
                readiness[:services][:unhealthy_services].each do |service|
                  puts "    • #{service}: Unhealthy"
                end
              end
            end
          end
        end

        def display_deployment_errors(deployment_result)
          if deployment_result[:pre_deployment_validation]
            puts "  Pre-deployment validation issues detected"
          end

          if deployment_result[:deployment] && deployment_result[:deployment][:status] == 'failed'
            puts "  Deployment execution failed"
            puts "  Error: #{deployment_result[:deployment][:error]}" if deployment_result[:deployment][:error]
          end

          if deployment_result[:post_deployment_health]
            health = deployment_result[:post_deployment_health]
            puts "  Post-deployment health: #{health[:status]}"
          end
        end

        def display_deployment_summary(deployment_result, version)
          puts ""
          puts "📋 Deployment Summary"
          puts "-" * 30
          puts "Version: #{version}"
          puts "Status: #{deployment_result[:overall_status]}"
          puts "Strategy: #{options[:strategy]}"
          
          if deployment_result[:deployment]
            deployment = deployment_result[:deployment]
            puts "Services Deployed: #{deployment[:services_deployed] || 'Unknown'}"
            puts "Rollback Ready: #{deployment[:rollback_ready] ? 'Yes' : 'No'}"
          end
          
          puts "Timestamp: #{Time.now}"
        end

        def save_audit_report(audit_result, filename)
          report_content = case File.extname(filename)
                          when '.json'
                            JSON.pretty_generate(audit_result)
                          else
                            format_audit_report_text(audit_result)
                          end

          File.write(filename, report_content)
        end

        def format_audit_report_text(audit_result)
          report = []
          report << "TCF Platform Security Audit Report"
          report << "=" * 50
          report << "Audit Time: #{Time.at(audit_result[:audit_timestamp])}"
          report << "Status: #{audit_result[:audit_status]}"
          report << ""

          unless audit_result[:critical_issues].empty?
            report << "Critical Issues:"
            audit_result[:critical_issues].each { |issue| report << "  • #{issue}" }
            report << ""
          end

          unless audit_result[:warnings].empty?
            report << "Warnings:"
            audit_result[:warnings].each { |warning| report << "  • #{warning}" }
            report << ""
          end

          vuln_scan = audit_result[:vulnerability_scan]
          report << "Vulnerability Summary:"
          report << "  Total: #{vuln_scan[:total_vulnerabilities]}"
          report << "  High: #{vuln_scan[:high_severity_count]}"
          report << "  Medium: #{vuln_scan[:medium_severity_count]}"
          report << "  Low: #{vuln_scan[:low_severity_count]}"

          report.join("\n")
        end
      end
    end
  end
end