# Graph Report - b-aws-tf-gha-landing-zone  (2026-06-26)

## Corpus Check
- 33 files · ~10,946 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 59 nodes · 48 edges · 15 communities (7 shown, 8 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7f805d77`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]

## God Nodes (most connected - your core abstractions)
1. `Module Reference` - 9 edges
2. `AWS Terraform Infrastructure Resource Summary` - 9 edges
3. `Architecture Overview` - 5 edges
4. `CI/CD Workflows` - 3 edges
5. `Observations` - 3 edges
6. `drift-check Job` - 3 edges
7. `Spoke VPCs (4 × Dev, Test, Prod, Shared)` - 2 edges
8. `Terraform Plan Detailed Exitcode Step` - 2 edges
9. `Terraform Plan Job` - 2 edges
10. `Terraform Apply Job` - 2 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Landing Zone CI/CD Workflow Pair** — terraform_plan_apply_yml_workflow, drift_detection_yml_workflow, oidc_role_assumption_concept, production_environment_gate [EXTRACTED 1.00]
- **IAM Permission Boundary Statements** — claude_md_deny_cross_environment_access, claude_md_deny_disabling_security, claude_md_deny_outside_home_region, claude_md_module_iam_boundaries [EXTRACTED 1.00]
- **Hub Root Module Composition** — claude_md_environments_hub_main, claude_md_module_vpc, claude_md_module_transit_gateway, claude_md_module_iam_boundaries, claude_md_module_logging, claude_md_module_security_baseline, claude_md_module_backup, claude_md_module_github_oidc [EXTRACTED 1.00]

## Communities (15 total, 8 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.22
Nodes (9): `environments/hub/main.tf`, Module Reference, `modules/backup/`, `modules/github-oidc/`, `modules/iam-boundaries/`, `modules/logging/`, `modules/security-baseline/`, `modules/transit-gateway/` (+1 more)

### Community 3 - "Community 3"
Cohesion: 0.33
Nodes (6): Configure AWS Credentials OIDC Step, drift-check Job, Drift Detection via plan -detailed-exitcode, Open Issue If Drift Detected Step, Terraform Plan Detailed Exitcode Step, drift-detection GitHub Workflow

### Community 5 - "Community 5"
Cohesion: 0.50
Nodes (4): Terraform Apply Job, Download Plan Artifact Step, Terraform Plan Job, Upload Plan Artifact Step

### Community 8 - "Community 8"
Cohesion: 0.20
Nodes (9): Bootstrap Process (chicken-and-egg), Caveats, CI/CD Workflows, Common Commands, `.github/workflows/drift-detection.yml`, `.github/workflows/terraform-plan-apply.yml`, graphify, Key Cross-Module Wiring (+1 more)

### Community 10 - "Community 10"
Cohesion: 0.40
Nodes (5): Architecture Overview, Hub-and-Spoke Network Topology, Key Configuration Details, Module Boundaries (Enterprise Concept Analogy), Repo Layout

### Community 11 - "Community 11"
Cohesion: 0.20
Nodes (10): AWS Backup, AWS Terraform Infrastructure Resource Summary, GitHub OIDC Integration, IAM Boundaries, Logging, Per Spoke, Resource Inventory, Security Baseline (+2 more)

### Community 14 - "Community 14"
Cohesion: 0.40
Nodes (4): Good Practices, Improvements Required, Observations, Overall Summary

## Knowledge Gaps
- **41 isolated node(s):** `Hub-and-Spoke Network Topology`, `Module Boundaries (Enterprise Concept Analogy)`, `Repo Layout`, `Key Configuration Details`, `Common Commands` (+36 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AWS Terraform Infrastructure Resource Summary` connect `Community 11` to `Community 14`?**
  _High betweenness centrality (0.179) - this node is a cross-community bridge._
- **Why does `Module Reference` connect `Community 0` to `Community 8`?**
  _High betweenness centrality (0.162) - this node is a cross-community bridge._
- **Why does `Architecture Overview` connect `Community 10` to `Community 8`?**
  _High betweenness centrality (0.086) - this node is a cross-community bridge._
- **What connects `Hub-and-Spoke Network Topology`, `Module Boundaries (Enterprise Concept Analogy)`, `Repo Layout` to the rest of the system?**
  _44 weakly-connected nodes found - possible documentation gaps or missing edges._