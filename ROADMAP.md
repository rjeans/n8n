# n8n GCP Migration - Implementation Roadmap

This document outlines the complete roadmap for migrating n8n from a homelab Kubernetes cluster to a GCP e2-micro instance.

## Project Status

**Current Phase**: Infrastructure Setup
**Last Updated**: 2025-10-19
**Target Completion**: TBD

## Phase Overview

- [x] Phase 0: Planning & Design
- [ ] Phase 1: Infrastructure Provisioning
- [ ] Phase 2: Application Stack Deployment
- [ ] Phase 3: Data Migration
- [ ] Phase 4: Cutover & Validation
- [ ] Phase 5: Optimization & Monitoring

---

## Phase 0: Planning & Design ✅

**Status**: Complete
**Duration**: N/A

### Tasks

- [x] Define architecture (Docker Compose + Cloudflare Tunnel)
- [x] Select GCP instance type (e2-micro)
- [x] Design project structure
- [x] Plan migration strategy
- [x] Create documentation framework

### Deliverables

- [x] README.md
- [x] ROADMAP.md (this file)
- [x] Project directory structure

---

## Phase 1: Infrastructure Provisioning

**Status**: Not Started
**Estimated Duration**: 1-2 hours

### Objectives

Provision and configure GCP infrastructure using Terraform, ensuring all resources are properly configured and accessible.

### Tasks

#### 1.1 Terraform Configuration
- [ ] Create `main.tf` with GCP provider configuration
- [ ] Define compute instance resource (e2-micro)
- [ ] Configure firewall rules (SSH only, Cloudflare Tunnel handles ingress)
- [ ] Set up persistent disk for data storage
- [ ] Create `variables.tf` for parameterization
- [ ] Create `outputs.tf` for instance details
- [ ] Create `terraform.tfvars.example` template

#### 1.2 GCP Project Setup
- [ ] Create/select GCP project
- [ ] Enable required APIs:
  - Compute Engine API
  - Cloud Resource Manager API
- [ ] Set up billing (if not already configured)
- [ ] Configure service account for Terraform
- [ ] Generate and store credentials

#### 1.3 Infrastructure Deployment
- [ ] Initialize Terraform (`terraform init`)
- [ ] Validate configuration (`terraform validate`)
- [ ] Review plan (`terraform plan`)
- [ ] Apply configuration (`terraform apply`)
- [ ] Verify instance creation and accessibility
- [ ] Test SSH access to instance

### Success Criteria

- [ ] GCP e2-micro instance running
- [ ] SSH access working
- [ ] Persistent disk attached and mounted
- [ ] Terraform state properly managed
- [ ] All outputs documented

### Blockers/Risks

- GCP quota limitations
- API enablement delays
- SSH key configuration issues

---

## Phase 2: Application Stack Deployment

**Status**: Not Started
**Estimated Duration**: 2-3 hours

### Objectives

Deploy the complete n8n stack using Docker Compose with PostgreSQL database and Cloudflare Tunnel.

### Tasks

#### 2.1 Server Preparation
- [ ] SSH to GCP instance
- [ ] Update system packages (`apt update && apt upgrade`)
- [ ] Install Docker and Docker Compose
- [ ] Configure Docker to start on boot
- [ ] Create application directory structure
- [ ] Set up user permissions for Docker

#### 2.2 Docker Compose Configuration
- [ ] Create `docker-compose.yml` with services:
  - n8n container (latest stable version)
  - PostgreSQL container (v16 or latest stable)
  - cloudflared container
- [ ] Configure persistent volumes:
  - PostgreSQL data volume
  - n8n data volume (workflows, credentials)
- [ ] Set up Docker networks for service communication
- [ ] Create `.env.example` template
- [ ] Configure `.env` with production values

#### 2.3 Cloudflare Tunnel Setup
- [ ] Create Cloudflare Tunnel in dashboard
- [ ] Generate tunnel credentials
- [ ] Create `docker/cloudflared/config.yml`
- [ ] Configure ingress rules for n8n
- [ ] Create `setup-cloudflared.sh` script
- [ ] Configure DNS records in Cloudflare

#### 2.4 Initial Deployment
- [ ] Copy configuration files to server
- [ ] Review and validate all environment variables
- [ ] Deploy stack (`docker-compose up -d`)
- [ ] Verify all containers are running
- [ ] Check logs for errors
- [ ] Test internal connectivity between services

#### 2.5 External Access Validation
- [ ] Verify Cloudflare Tunnel status
- [ ] Test HTTPS access via domain
- [ ] Verify SSL certificate (Cloudflare managed)
- [ ] Test n8n login page accessibility
- [ ] Validate basic authentication

### Success Criteria

- [ ] All containers running without errors
- [ ] n8n accessible via Cloudflare domain
- [ ] HTTPS working properly
- [ ] PostgreSQL accepting connections from n8n
- [ ] Cloudflare Tunnel connected and healthy
- [ ] Persistent volumes working correctly

### Blockers/Risks

- Docker installation issues on GCP instance
- Cloudflare Tunnel connectivity problems
- DNS propagation delays
- Container networking issues

---

## Phase 3: Data Migration

**Status**: Complete (Manual Migration)
**Estimated Duration**: 2-4 hours

### Objectives

Migrate all workflows, credentials, and data from the existing Kubernetes-based n8n instance to the new GCP instance.

### Tasks

#### 3.1 Pre-Migration Assessment
- [x] Document current K8s n8n version
- [x] List all active workflows
- [x] Identify all credentials and connections
- [x] Check for custom nodes or integrations
- [x] Estimate database size
- [x] Plan maintenance window

#### 3.2 Backup from K8s Cluster
- [x] Export n8n workflows via API/CLI
- [x] Export credentials (encrypted)
- [x] Backup PostgreSQL database
- [x] Document n8n configuration settings
- [x] Save environment variables

#### 3.3 Data Transfer
- [x] Transfer backup files to GCP instance
- [x] Verify file integrity after transfer
- [x] Create staging directory on GCP instance
- [x] Decompress backup files

#### 3.4 Database Migration
- [x] Stop n8n container temporarily
- [x] Restore PostgreSQL database
- [x] Verify table counts and data
- [x] Run any necessary migrations

#### 3.5 Workflow & Credentials Import
- [x] Import workflows via n8n API
- [x] Import credentials
- [x] Verify encryption key matches
- [x] Update environment-specific settings
- [x] Test sample workflows

#### 3.6 Validation
- [x] Start n8n container
- [x] Verify all workflows appear in UI
- [x] Check all credentials are accessible
- [x] Test webhook URLs with new domain
- [x] Validate database connections
- [x] Check execution history
- [x] Test trigger-based workflows
- [x] Run manual workflow executions

**Note**: Migration was completed manually. Automated migration scripts available in `scripts/migrate-from-k8s.sh` for reference.

### Success Criteria

- [x] All workflows migrated successfully
- [x] All credentials accessible and working
- [x] Database fully restored with all data
- [x] n8n version upgraded safely
- [x] No data loss or corruption
- [x] Sample workflows execute successfully

### Blockers/Risks

- Version incompatibility between old and new n8n
- Encryption key mismatch (credentials unrecoverable!)
- Database corruption during transfer
- Large database size causing timeout issues
- Network transfer interruptions

---

## Phase 4: Cutover & Validation

**Status**: Not Started
**Estimated Duration**: 1-2 hours + monitoring period

### Objectives

Switch production traffic to the new GCP instance and validate complete functionality.

### Tasks

#### 4.1 Pre-Cutover Checklist
- [ ] Complete final backup of K8s instance
- [ ] Verify all workflows tested on new instance
- [ ] Document rollback procedure
- [ ] Prepare monitoring dashboard
- [ ] Notify stakeholders of maintenance window
- [ ] Disable triggers on K8s instance

#### 4.2 DNS & Traffic Cutover
- [ ] Update webhook URLs in external systems
- [ ] Update API endpoints if hardcoded anywhere
- [ ] Verify Cloudflare DNS routing
- [ ] Test new URLs from external location
- [ ] Monitor Cloudflare Tunnel metrics

#### 4.3 Post-Cutover Validation
- [ ] Execute test workflows manually
- [ ] Verify scheduled workflows trigger correctly
- [ ] Check webhook endpoints receiving data
- [ ] Monitor system resources (CPU, memory, disk)
- [ ] Check Docker container logs
- [ ] Verify database performance
- [ ] Test all integrations

#### 4.4 Monitoring Period
- [ ] Monitor for 24 hours minimum
- [ ] Track workflow execution success rate
- [ ] Monitor error logs
- [ ] Check system resource usage trends
- [ ] Validate backup automation working

#### 4.5 K8s Decommission (After Successful Validation)
- [ ] Stop K8s n8n deployment
- [ ] Create final archive backup
- [ ] Store backup in safe location
- [ ] Document shutdown date
- [ ] Remove K8s resources
- [ ] Update documentation

### Success Criteria

- [ ] Zero downtime during cutover
- [ ] All workflows executing successfully
- [ ] No increase in error rates
- [ ] System performance acceptable
- [ ] All integrations working
- [ ] Backups running automatically
- [ ] Monitoring in place

### Blockers/Risks

- DNS propagation issues
- Webhook endpoint updates missed
- Performance issues on e2-micro instance
- Unexpected workflow failures
- Integration authentication issues

---

## Phase 5: Optimization & Monitoring

**Status**: Not Started
**Estimated Duration**: Ongoing

### Objectives

Optimize the deployment, implement monitoring, and establish maintenance procedures.

### Tasks

#### 5.1 Performance Optimization
- [ ] Analyze resource usage patterns
- [ ] Optimize Docker resource limits
- [ ] Configure PostgreSQL performance settings
- [ ] Implement database connection pooling
- [ ] Review and optimize workflow efficiency
- [ ] Configure log rotation
- [ ] Optimize disk I/O if needed

#### 5.2 Backup & Disaster Recovery
- [ ] Create `backup.sh` script with:
  - PostgreSQL database backup
  - n8n data volume backup
  - Configuration files backup
- [ ] Set up automated backups (cron)
- [ ] Test restore procedures
- [ ] Configure backup retention policy
- [ ] Implement off-instance backup storage (GCS bucket)
- [ ] Document recovery procedures

#### 5.3 Monitoring & Alerting
- [ ] Set up Docker container health checks
- [ ] Configure system resource monitoring
- [ ] Implement log aggregation
- [ ] Create alerting for critical errors
- [ ] Monitor disk space usage
- [ ] Track workflow execution metrics
- [ ] Set up uptime monitoring

#### 5.4 Security Hardening
- [ ] Review firewall rules
- [ ] Implement fail2ban for SSH
- [ ] Configure automatic security updates
- [ ] Review n8n security settings
- [ ] Implement secrets management best practices
- [ ] Regular security audit schedule
- [ ] Document security procedures

#### 5.5 Documentation & Runbooks
- [ ] Complete `docs/SETUP.md`
- [ ] Complete `docs/TROUBLESHOOTING.md`
- [ ] Create operational runbooks:
  - Backup and restore procedures
  - Update procedures
  - Incident response
  - Scaling considerations
- [ ] Document common maintenance tasks
- [ ] Create disaster recovery plan

#### 5.6 Automation Scripts
- [ ] `deploy.sh` - Automated deployment
- [ ] `backup.sh` - Backup automation
- [ ] `update.sh` - Update n8n and containers
- [ ] `health-check.sh` - System health validation
- [ ] Make all scripts executable and tested

### Success Criteria

- [ ] Complete backup automation in place
- [ ] Monitoring and alerting configured
- [ ] All scripts tested and documented
- [ ] Performance optimized for workload
- [ ] Security hardening complete
- [ ] Documentation comprehensive and up-to-date

### Ongoing Tasks

- Regular security updates
- Monitoring and performance reviews
- Backup validation
- Cost optimization reviews
- Documentation updates

---

## Risk Management

### High Priority Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Data loss during migration | High | Multiple backups, validation steps, tested rollback procedure |
| Encryption key mismatch | High | Document and verify encryption key before migration |
| e2-micro insufficient resources | Medium | Monitor during testing, plan for upgrade path if needed |
| Extended downtime | Medium | Thorough testing, detailed runbooks, practice runs |

### Contingency Plans

**If migration fails:**
1. Roll back to K8s instance (keep running during validation)
2. Investigate issues
3. Fix and retry migration

**If performance inadequate:**
1. Optimize configurations
2. Consider instance upgrade (e2-small)
3. Evaluate workflow efficiency

**If data corruption occurs:**
1. Restore from K8s backup
2. Retry migration with additional validation
3. Consider incremental migration approach

---

## Success Metrics

### Technical Metrics
- [ ] 100% workflow migration success rate
- [ ] <1% increase in workflow execution errors
- [ ] <5 second response time for n8n UI
- [ ] >99% uptime after cutover
- [ ] Successful automated backups

### Operational Metrics
- [ ] Complete documentation
- [ ] All automation scripts functional
- [ ] Monitoring coverage >90%
- [ ] Recovery procedures tested

### Cost Metrics
- [ ] Monthly cost <$5
- [ ] Within GCP free tier limits

---

## Timeline

| Phase | Estimated Duration | Target Completion |
|-------|-------------------|-------------------|
| Phase 0: Planning | Complete | ✅ |
| Phase 1: Infrastructure | 1-2 hours | TBD |
| Phase 2: Application Stack | 2-3 hours | TBD |
| Phase 3: Data Migration | 2-4 hours | TBD |
| Phase 4: Cutover | 1-2 hours + 24h monitoring | TBD |
| Phase 5: Optimization | Ongoing | TBD |

**Total Estimated Time**: 8-14 hours + ongoing optimization

---

## Notes & Decisions

### Key Decisions
- **Docker Compose over K8s**: Simpler for single-instance deployment
- **Cloudflare Tunnel over Load Balancer**: No cost, no port exposure
- **e2-micro instance**: Free tier eligible, sufficient for moderate workloads
- **PostgreSQL in Docker**: Simpler than managed database for this scale

### Assumptions
- Current n8n workload fits within e2-micro resources
- Moderate workflow execution frequency
- Database size <10GB
- Network egress <1GB/month

### Open Questions
- [ ] Current n8n version in K8s?
- [ ] Estimated workflow count?
- [ ] Database size?
- [ ] Expected concurrent executions?
- [ ] Backup retention requirements?

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-10-19 | Initial roadmap creation | Claude |

---

## References

- [n8n Documentation](https://docs.n8n.io/)
- [GCP e2-micro Specifications](https://cloud.google.com/compute/docs/machine-types#e2_machine_types)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
