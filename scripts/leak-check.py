# Post-destroy leak check for the dev environment (docs/runbooks/teardown.md).
#
# Runs through the AWS MCP Server's run_script tool, where `call_boto3` is
# already defined. Read-only: Describe* calls only. Counts what is left in
# eu-west-2 after `terraform destroy`, prints one line per resource type, and
# fails (non-zero exit) if anything is left.

REGION = "eu-west-2"
CLUSTER = "aws-platform-dev"
PROJECT = {"Project": "aws-platform"}
PROJECT_DEV = {"Project": "aws-platform", "Environment": "dev"}


async def call(service, operation, **params):
    return await call_boto3(
        service_name=service, operation_name=operation, region_name=REGION, params=params
    )


def tag_filters(tags):
    return [{"Name": f"tag:{k}", "Values": [v]} for k, v in tags.items()]


def is_ours(tags):
    """tags is a list of {"Key", "Value"} as returned by elbv2 DescribeTags."""
    d = {t["Key"]: t["Value"] for t in tags}
    return d.get("Project") == "aws-platform" or d.get("elbv2.k8s.aws/cluster") == CLUSTER


async def elbv2_ours(describe_op, list_key, arn_key):
    resources = (await call("elbv2", describe_op))[list_key]
    arns = [r[arn_key] for r in resources]
    found = []
    for i in range(0, len(arns), 20):  # DescribeTags takes at most 20 ARNs
        batch = arns[i : i + 20]
        for desc in (await call("elbv2", "DescribeTags", ResourceArns=batch))["TagDescriptions"]:
            if is_ours(desc["Tags"]):
                found.append(desc["ResourceArn"])
    return found


async def vpc_ids():
    # The VPC by its Name tag, or by the project tags (union).
    ids = set()
    for filters in (
        [{"Name": "tag:Name", "Values": [CLUSTER]}],
        tag_filters(PROJECT_DEV),
    ):
        ids.update(v["VpcId"] for v in (await call("ec2", "DescribeVpcs", Filters=filters))["Vpcs"])
    return sorted(ids)


async def ids_by_vpc_or_tags(operation, list_key, id_key, vpcs, extra=()):
    """Resources in the VPCs, plus those carrying the project tags (union)."""
    found = {}
    queries = [tag_filters(PROJECT_DEV) + list(extra)]
    if vpcs:  # an empty vpc-id filter would match everything
        queries.append([{"Name": "vpc-id", "Values": vpcs}] + list(extra))
    for filters in queries:
        for r in (await call("ec2", operation, Filters=filters))[list_key]:
            found[r[id_key]] = r
    return found


vpcs = await vpc_ids()
counts = {}

counts["load balancers"] = len(await elbv2_ours("DescribeLoadBalancers", "LoadBalancers", "LoadBalancerArn"))
counts["target groups"] = len(await elbv2_ours("DescribeTargetGroups", "TargetGroups", "TargetGroupArn"))

# A deleted NAT gateway stays visible for about an hour in state "deleted": not a leak.
nat_state = [{"Name": "state", "Values": ["pending", "available", "deleting"]}]
counts["NAT gateways"] = len(await ids_by_vpc_or_tags("DescribeNatGateways", "NatGateways", "NatGatewayId", vpcs, nat_state))

# Elastic IPs have no VPC ID: found by the project tags or the Name prefix.
eips = {}
for filters in (tag_filters(PROJECT_DEV), [{"Name": "tag:Name", "Values": [CLUSTER + "*"]}]):
    for a in (await call("ec2", "DescribeAddresses", Filters=filters))["Addresses"]:
        eips[a["AllocationId"]] = a
counts["Elastic IPs"] = len(eips)

counts["network interfaces"] = len(await ids_by_vpc_or_tags("DescribeNetworkInterfaces", "NetworkInterfaces", "NetworkInterfaceId", vpcs))

# Only unattached volumes count: attached ones go away with their instance.
available = [{"Name": "status", "Values": ["available"]}]
volumes = (await call("ec2", "DescribeVolumes", Filters=tag_filters(PROJECT_DEV) + available))["Volumes"]
counts["unattached EBS volumes"] = len(volumes)

counts["VPC still exists"] = len(vpcs)

for name, n in counts.items():
    print(f"{name}: {n}")
leftovers = {k: v for k, v in counts.items() if v}
print("PASS: nothing left" if not leftovers else f"FAIL: {', '.join(leftovers)} not clean")

result = {"status": "FAIL" if leftovers else "PASS", "counts": counts, "vpc_ids": vpcs}
if leftovers:
    raise SystemExit(1)
result
