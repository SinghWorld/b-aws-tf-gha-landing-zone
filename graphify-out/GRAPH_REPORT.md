# Graph Report - .  (2026-06-25)

## Corpus Check
- Corpus is ~9,979 words - fits in a single context window. You may not need a graph.

## Summary
- 41 nodes · 51 edges · 10 communities (6 shown, 4 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 5 edges (avg confidence: 0.91)
- Token cost: 0 input · 0 output

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

## God Nodes (most connected - your core abstractions)
1. `Repository Layout` - 10 edges
2. `environments/hub/main.tf Root Composition` - 10 edges
3. `modules/iam-boundaries Module` - 5 edges
4. `modules/security-baseline Module` - 5 edges
5. `modules/github-oidc Module` - 5 edges
6. `Known Caveats and Limitations` - 5 edges
7. `modules/logging Module` - 4 edges
8. `GitHub OIDC Role Assumption Pattern` - 4 edges
9. `modules/vpc Module` - 3 edges
10. `modules/transit-gateway Module` - 3 edges

## Surprising Connections (you probably didn't know these)
- `README Known Caveats` --semantically_similar_to--> `Known Caveats and Limitations`  [INFERRED] [semantically similar]
  README.md → CLAUDE.md
- `Personal AWS Landing Zone README Overview` --semantically_similar_to--> `Landing Zone Architecture Overview`  [INFERRED] [semantically similar]
  README.md → CLAUDE.md
- `README Architecture Diagram` --semantically_similar_to--> `Hub-and-Spoke Network Topology`  [INFERRED] [semantically similar]
  README.md → CLAUDE.md
- `Repository Layout` --references--> `drift-detection GitHub Workflow`  [EXTRACTED]
  CLAUDE.md → landing-zone/.github/workflows/drift-detection.yml
- `Repository Layout` --references--> `terraform-plan-apply GitHub Workflow`  [EXTRACTED]
  CLAUDE.md → landing-zone/.github/workflows/terraform-plan-apply.yml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Landing Zone CI/CD Workflow Pair** — terraform_plan_apply_yml_workflow, drift_detection_yml_workflow, oidc_role_assumption_concept, production_environment_gate [EXTRACTED 1.00]
- **IAM Permission Boundary Statements** — claude_md_deny_cross_environment_access, claude_md_deny_disabling_security, claude_md_deny_outside_home_region, claude_md_module_iam_boundaries [EXTRACTED 1.00]
- **Hub Root Module Composition** — claude_md_environments_hub_main, claude_md_module_vpc, claude_md_module_transit_gateway, claude_md_module_iam_boundaries, claude_md_module_logging, claude_md_module_security_baseline, claude_md_module_backup, claude_md_module_github_oidc [EXTRACTED 1.00]

## Communities (10 total, 4 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.57
Nodes (8): Cross-Module Topological Wiring, environments/hub/main.tf Root Composition, modules/backup Module, modules/logging Module, modules/security-baseline Module, modules/transit-gateway Module, modules/vpc Module, Repository Layout

### Community 1 - "Community 1"
Cohesion: 0.33
Nodes (7): Two-Phase Bootstrap Process, Key Configuration Details, modules/github-oidc Module, GitHub OIDC Role Assumption Pattern, Production Environment Manual Approval Gate, Prerequisites for Setup, terraform-plan-apply GitHub Workflow

### Community 2 - "Community 2"
Cohesion: 0.33
Nodes (6): Known Caveats and Limitations, IAM DenyCrossEnvironmentAccess Statement, IAM DenyDisablingSecurityTooling Statement, IAM DenyOutsideHomeRegion Statement, modules/iam-boundaries Module, README Known Caveats

### Community 3 - "Community 3"
Cohesion: 0.33
Nodes (6): Configure AWS Credentials OIDC Step, drift-check Job, Drift Detection via plan -detailed-exitcode, Open Issue If Drift Detected Step, Terraform Plan Detailed Exitcode Step, drift-detection GitHub Workflow

### Community 4 - "Community 4"
Cohesion: 0.50
Nodes (4): Hub-and-Spoke Network Topology, Landing Zone Architecture Overview, README Architecture Diagram, Personal AWS Landing Zone README Overview

### Community 5 - "Community 5"
Cohesion: 0.50
Nodes (4): Terraform Apply Job, Download Plan Artifact Step, Terraform Plan Job, Upload Plan Artifact Step

## Knowledge Gaps
- **8 isolated node(s):** `01.setup_s3-backend.sh script`, `02.destroy-s3-backend.sh script`, `Personal AWS Landing Zone README Overview`, `README Architecture Diagram`, `Open Issue If Drift Detected Step` (+3 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Repository Layout` connect `Community 0` to `Community 1`, `Community 2`, `Community 3`?**
  _High betweenness centrality (0.191) - this node is a cross-community bridge._
- **Why does `drift-detection GitHub Workflow` connect `Community 3` to `Community 0`, `Community 1`?**
  _High betweenness centrality (0.140) - this node is a cross-community bridge._
- **What connects `01.setup_s3-backend.sh script`, `02.destroy-s3-backend.sh script`, `Enterprise Concept to Implementation Mapping` to the rest of the system?**
  _15 weakly-connected nodes found - possible documentation gaps or missing edges._