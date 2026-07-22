# AWS Cost Estimate — UAT (ssw_ndid_api)

Estimate for the **default Terraform config** in `terraform/envs/uat` (always-on, region **ap-southeast-1**, low UAT traffic).

- Currency: USD/month, excludes tax.
- Rates: approximate ap-southeast-1 (Singapore) list prices as of 2026 — **not a live quote**.
- For an exact figure: AWS Pricing Calculator, or `terraform plan` + [Infracost](https://infracost.io) once the account exists.

## Monthly baseline

| Resource | Spec (from `terraform.tfvars.example` defaults) | ~$/mo |
|---|---|---|
| NAT Gateway | 1 gateway (single) + low data processing | 45 |
| ECS Fargate — ndid-api | 0.5 vCPU / 1 GB, 1 task, 24/7 | 23 |
| ECS Fargate — grafana | 0.25 vCPU / 0.5 GB, 1 task, 24/7 | 11 |
| RDS PostgreSQL | db.t3.micro single-AZ + 20 GB gp3 | 22 |
| ALB | 1 ALB + ~1 LCU | 20 |
| CloudWatch Logs | low UAT volume (~few GB) | 4 |
| KMS | 1 customer-managed key | 1 |
| Route 53 | 1 hosted zone (if newly created) | 0.50 |
| ECR / S3 state / S3 ALB-logs / SSM | few GB; SSM SecureString standard tier = free | ~2 |
| Data transfer out | low | 1–5 |
| **Total baseline** | | **≈ 130** |

Realistic range **$120–160/mo** depending on traffic and auto-scale spikes during test cycles.

## Cost drivers
NAT Gateway, RDS, ALB, and Fargate are roughly equal quarters and together ~90% of the bill.

## Levers to reduce cost
| Lever | Effect | Trade-off |
|---|---|---|
| NAT instance (t4g.nano) instead of managed NAT Gateway | −~$40/mo | Self-managed; less resilient. Needed at all because private-subnet tasks must reach DAP over the internet (SECURITY-07); cannot drop entirely without public IPs on tasks. |
| Scale-to-zero off-hours (stop Fargate + RDS outside test windows) | −40–50% | Requires a start step before each test session (you chose always-on, decision 11B) |
| Fargate Spot for UAT | compute −~70% (~$34 → ~$10) | Tasks can be interrupted; acceptable for non-prod |
| RDS / Fargate sizing | already smallest sensible | — |

## Notes
- `rds_multi_az = true` (production-like) roughly **doubles** the RDS line (~$22 → ~$44).
- Auto-scaling (`api_max_count = 4`) only adds cost when CPU sustains >65%; UAT baseline stays at 1 task.
- One-time / usage-variable: NAT data processing ($/GB), data transfer out, CloudWatch ingestion scale with actual use.
