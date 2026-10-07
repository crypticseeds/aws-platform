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
| 7 | Argo CD installed with an app-of-apps root; Helm charts for both apps; platform add-ons (load balancer controller, kube-prometheus-stack, metrics-server) as Argo apps | DEV-139, DEV-140, DEV-141, DEV-142 | Merged, **UNVERIFIED live** | Charts: PRs #3 and #5. Argo and add-ons: PRs #6, #10 and landing PR #11 (merged 2026-10-05). Offline evidence is in the issue comments (helm lint, kubeconform, CRD-schema validation, security-context extract). Nothing here has run on a cluster: no `root` app Synced/Healthy, no ALB created, no `kubectl top nodes` |
| 8 | Gateway and Promscope deployed through Argo and reachable end to end through the ALB | DEV-143 | Pending | PR #21 open, `checks` run 37547937299 green. Not merged, not run on a cluster |
| 9 | Observability wired: scrape targets, gateway dashboard, a Promscope query | DEV-144 | Pending | Issue is Todo in Linear. No PR yet |
| 10 | Teardown runbook, and a clean destroy with a leak check | DEV-145 | Runbook merged. The runbook drill is **UNVERIFIED** | PR #13 (merged 2026-10-05). The only destroy actually evidenced is the 2026-10-04 destroy of 61 resources with a 0-leak check (DEV-132 comment). The destroy of the full stack including Argo and the ALB has not been run |
| 11 | Architecture and cost docs, with estimate and first-week actuals | DEV-146 | Estimate Done, actuals Pending | PR #14 (merged 2026-10-05) holds `docs/architecture.md` and `docs/cost.md`. The DEV-146 comment says actuals are a placeholder until Cost Explorer has data after the first apply |
| 12 | Agent has read-only Kubernetes access with no Secrets | DEV-136 | Merged, **UNVERIFIED live** | PR #18 (merged 2026-10-06) and the DEV-136 comment of 2026-10-06. The access entry only exists after the owner applies `envs/dev`. The pods-yes, secrets-Forbidden check needs a cluster |
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

1. Live evidence for DEV-143 and DEV-144 (an ALB reachable end to end, a dashboard, a Promscope query), from a cluster session run by the owner.
2. Live checks for DEV-136, DEV-141, DEV-142: RBAC (no Secrets), `root` Synced/Healthy, no stray load balancer, `kubectl top nodes`.
3. A destroy decision: destroy and run the leak check, or keep the stack with a reason written down.
4. Owner confirmation that the criteria list matches the handoff and that the phase is done.
