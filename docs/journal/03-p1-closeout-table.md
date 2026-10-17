# P1 close-out: criteria table (DRAFT)

Draft for DEV-147, prepared 2026-10-07. Not final: DEV-143 and DEV-144 are still being written and nothing that needs a running cluster has been verified. The coordinator updates the status column at close-out, and the owner confirms the phase.

## How to read this

- **Done** means the issue's own evidence exists and was looked at (a merged PR, a CI run, a Docker Hub query or a Linear comment with agent read-only output).
- **Pending** means the work is not finished or not merged.
- **UNVERIFIED** is written next to any item whose code is merged but whose live behaviour has not been seen, because the cluster is destroyed each session. It is never counted as done.
- **Not a gate** means the issue does not block the phase.

## Source of the criteria: PROPOSED rows

The brief asks for "handoff section 6, items 1-9". That handoff (`aws-platform-handoff.md`) is kept outside the public repo, and it was not available to the agent that wrote this draft. The Linear project description holds the Definition of Done but not the nine P1 criteria, and DEV-147 only refers to them. The rows below are therefore **PROPOSED**: they are derived from the P1 milestone description in Linear ("Terraform from a clean account to EKS with Argo CD, gateway and Promscope live behind an ALB, observability wired, docs written, and one clean destroy") and from the P1 issues. The owner should compare them with the handoff and correct the wording or the count.

## Criteria table (PROPOSED)

| # | Criterion (PROPOSED) | Delivering issues | Status | Evidence |
|---|---|---|---|---|
| 1 | Repo has safety rails: no secret or account ID can easily reach the public repo | DEV-127 | Done | PR #1 (merged 2026-10-04); journal 03 step 3 and its verification table (gitleaks blocked a staged fake token) |
| 2 | Remote state with locking, readable by the owner only, the agent denied | DEV-130 | Done | PR #1; comments on DEV-130 and journal 03 (agent `GetObject` denied, second plan `No changes.`, `.tflock` seen during apply) |
| 3 | Dev VPC and EKS cluster built from Terraform, second plan empty | DEV-131, DEV-132 | Done | PR #1; DEV-132 comments of 2026-10-04 (agent read-only verification of cluster, nodes, add-ons, tags; owner `No changes.` plan; `kubectl get nodes` worked) |
| 4 | Decisions recorded as ADRs | DEV-128 | Done | PR #2 (merged 2026-10-04), `docs/decisions/0001` to `0011` |
| 5 | CI checks every PR: static checks, and a plan-only Terraform workflow through a read-only OIDC role | DEV-163, DEV-133, DEV-135 | Done (DEV-135 shows In Progress in Linear, see Notes) | PR #8 (static checks); PR #9 (OIDC role); PR #17 (plan workflow). DEV-133: agent read-only verification comment of 2026-10-06 (trust policy, policy simulation, Access Analyzer finding archived, 3600 s session, second plan `No changes.`). `terraform-plan` run 37392939869 on PR #17: `plan (bootstrap)`, `plan (account)` and `plan (envs/dev)` all succeeded, and PR #17 carries one plan comment per root |
| 6 | Images for the gateway and Promscope are built in CI and pushed to Docker Hub | DEV-137, DEV-138, DEV-162 | Done | Gateway: gateway PR #30, DEV-137 comment of 2026-10-06 (SHA tag and `latest`, same digest, linux/amd64). Promscope: promscope PR #1 merged 2026-10-05; Docker Hub tag listing shows two tags in `crypticseeds/promscope`, `latest` pushed 2026-10-05. The image running as UID 10001 is DEV-162's own evidence (DEV-139 comment) |
| 7 | Argo CD installed with an app-of-apps root; Helm charts for both apps; platform add-ons (load balancer controller, kube-prometheus-stack, metrics-server) as Argo apps | DEV-139, DEV-140, DEV-141, DEV-142 | Done (verified live 2026-10-10) | Charts: PRs #3 and #5. Argo and add-ons: PRs #6, #10 and landing PR #11. Live 2026-10-10 (journal 03 step 28): add-ons Synced/Healthy after the cert-manager fix (DEV-166, PR #33); 21 services, none LoadBalancer or NodePort; controller logs 0 `AccessDenied`; `kubectl top nodes` 40% and 59% memory. DEV-167 (PR #34, root deploys the platform only) is not yet proven on a fresh deploy |
| 8 | Gateway and Promscope deployed through Argo and reachable end to end through the ALB | DEV-143, DEV-164 | Done live 2026-10-10, except the tag bump test | PR #21 merged. Live: exactly one ALB, inbound TCP 80 from one /32 only (DEV-164); 2/2 targets healthy; `/v1/health` 200; streaming ending `data: [DONE]`; bursts 60/60 and 153/153 200; images match the pinned SHAs; 4 pods Ready with `dockerhub-pull`. The tag bump through a PR is **UNVERIFIED** |
| 9 | Observability wired: scrape targets, gateway dashboard, a Promscope query | DEV-144 | Partly verified; dashboard **UNVERIFIED** | PR #22 merged. Live 2026-10-10: 2 gateway + 2 Promscope targets up; Promscope check `OK ... 25 series`. The gateway dashboard was not visible in Grafana although `grafana-dashboards` was Synced/Healthy; cause unknown |
| 10 | Teardown runbook, and a clean destroy with a leak check | DEV-145 | Done (drill run 2026-10-10) | PR #13. 2026-10-10: Ingresses deleted first, ALB, target group and controller group at 0 by 19:41:03; `terraform destroy`; leak check `PASS: nothing left` about 19:57 (journal 03 step 28) |
| 11 | Architecture and cost docs, with estimate and first-week actuals | DEV-146 | Estimate Done, actuals Pending | PR #14 holds `docs/architecture.md` and `docs/cost.md`. Cost Explorer October to 2026-10-10: $0.79 account total; the 2026-10-10 session was not yet in Cost Explorer (estimate $1 to $1.50, unverified) |
| 12 | Agent has read-only Kubernetes access with no Secrets | DEV-136 | Done (verified live 2026-10-10) | PR #18. Live: listing pods works, listing Secrets `Forbidden` (journal 03 verification table) |
| 13 | Close-out journal and this table | DEV-147 | Pending | This draft and `docs/journal/03-terraform-foundation.md` |

The brief asks for nine criteria and the proposed list has thirteen rows, because the P1 issues split more finely than a nine-item list would. If the handoff has nine, the owner maps these rows onto them.

## Not a gate and other open P1 issues

| Issue | State in Linear on 2026-10-07 | Note |
|---|---|---|
| DEV-134 codify the account baseline (import) | Todo, priority Low | Not a gate, as DEV-147 says. The brief described it as in progress with two PRs pending, but Linear shows Todo |
| DEV-125 owner inputs | Todo | The Docker Hub namespace is in use (`crypticseeds`). Doppler names and domain: not checked |
| DEV-126 budgets and cost allocation tags | Backlog | Deferred by the owner (journal 03). Definition of Done item 9 (tags verified through the tagging API) depends on cost allocation tags being activated |
| DEV-129 close open access items from journals 01 and 02 | Todo | Not touched by this draft |
| DEV-161 move the agent to the Pi 5 | Todo, Urgent | Workflow item, not a P1 criterion |
| DEV-155 Argo CD hub on the Pi plus private endpoint | Backlog | Journal 03 expected this in P1. DEV-141 was corrected on 2026-10-04 to run Argo CD on EKS, so DEV-155 is a later step |

## Notes and inconsistencies found

- **DEV-135 is In Progress in Linear** although PR #17 is merged and all three plan jobs pass. The last DEV-135 comment predates the OIDC fix, and `.agent/HANDOFF.md` says it is Done. Linear needs a status check by the coordinator.
- **The Linear GitHub integration closes an issue when its PR merges**, even before the owner has applied and verified. DEV-133 had to be moved back to In Review for that reason. Other "Done" issues in this table were not re-checked for the same effect, so the evidence column, not the status in Linear, is what counts.
- **DEV-141 and DEV-142 were stacked PRs** that merged into other branches, not main. PR #11 landed them on main (DEV-141 comment of 2026-10-05).
- **Open PR #19** (secret format doc for DEV-135) is docs only and open. Its twin #20 was closed.

## What the close-out still needs

1. The DEV-144 gateway dashboard, checked live, and the DEV-143 tag bump test.
2. DEV-167's staged deploy proven on a fresh deploy.
3. Cost actuals for the 2026-10-10 session.
4. Owner confirmation that the criteria list matches the handoff and that the phase is done.
