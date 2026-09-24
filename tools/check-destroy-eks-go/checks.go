package main

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ecr"
	"github.com/aws/aws-sdk-go-v2/service/eks"
	"github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

// checkEC2Instances is the check the bash version and this tool's first
// version both lacked -- added to catch leftover worker nodes directly
// instead of relying on the network-interface check to indirectly notice
// them via their attached ENI's description.
//
// This used to server-side filter on tag:aws:eks:cluster-name, which was a
// guess at EKS's internal tagging convention -- and this project's own
// aws_launch_template.eks_node has no tag_specifications block, so nothing
// in this repo's own Terraform code puts a verified tag on these instances
// either. A wrong (or absent) tag meant the filter silently matched nothing,
// ever -- confirmed live: this check printed "(none)" while real instances
// were still sitting in the EC2 console needing manual termination. Fixed
// the same way every other check in this file already handles uncertain
// tagging (see checkLoadBalancers/checkSecurityGroups/checkNetworkInterfaces):
// list everything, then match client-side against every tag's key AND value,
// so it doesn't depend on guessing one exact tag key right.
func checkEC2Instances(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"InstanceId", "State", "InstanceType", "LaunchTime", "MatchedTag"}
	var rows [][]string

	paginator := ec2.NewDescribeInstancesPaginator(c.ec2, &ec2.DescribeInstancesInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, reservation := range page.Reservations {
			for _, inst := range reservation.Instances {
				// Terminated instances aren't costing anything and linger in
				// the API for a while before disappearing -- not real residue.
				if inst.State != nil && inst.State.Name == ec2types.InstanceStateNameTerminated {
					continue
				}
				matched := ""
				for _, t := range inst.Tags {
					key := aws.ToString(t.Key)
					val := aws.ToString(t.Value)
					if containsAny(key, p.clusterName, p.prefix) || containsAny(val, p.clusterName, p.prefix) {
						matched = fmt.Sprintf("%s=%s", key, val)
						break
					}
				}
				if matched == "" {
					continue
				}
				state := ""
				if inst.State != nil {
					state = string(inst.State.Name)
				}
				launchTime := ""
				if inst.LaunchTime != nil {
					launchTime = inst.LaunchTime.Format(time.RFC3339)
				}
				rows = append(rows, []string{
					aws.ToString(inst.InstanceId),
					state,
					string(inst.InstanceType),
					launchTime,
					matched,
				})
			}
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkEKSClusters(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"ClusterName"}
	out, err := c.eks.ListClusters(ctx, &eks.ListClustersInput{})
	if err != nil {
		return checkResult{headers: headers, err: err}
	}
	var rows [][]string
	for _, name := range out.Clusters {
		rows = append(rows, []string{name})
	}
	return checkResult{headers: headers, rows: rows}
}

func checkEKSNodegroups(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"Nodegroup"}
	out, err := c.eks.ListNodegroups(ctx, &eks.ListNodegroupsInput{ClusterName: aws.String(p.clusterName)})
	if err != nil {
		// Expected once the cluster is gone -- that's success for a destroy
		// check, but we still surface it the same way the bash version does
		// ("command failed; continuing") rather than special-casing it.
		return checkResult{headers: headers, err: err}
	}
	var rows [][]string
	for _, ng := range out.Nodegroups {
		rows = append(rows, []string{ng})
	}
	return checkResult{headers: headers, rows: rows}
}

func checkLoadBalancers(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"Name", "State", "Type", "VpcId"}
	var rows [][]string

	paginator := elasticloadbalancingv2.NewDescribeLoadBalancersPaginator(c.elbv2, &elasticloadbalancingv2.DescribeLoadBalancersInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, lb := range page.LoadBalancers {
			name := aws.ToString(lb.LoadBalancerName)
			if !containsAny(name, "k8s", p.prefix) {
				continue
			}
			state := ""
			if lb.State != nil {
				state = string(lb.State.Code)
			}
			rows = append(rows, []string{name, state, string(lb.Type), aws.ToString(lb.VpcId)})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkTargetGroups(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"Name", "Protocol", "Port", "VpcId"}
	var rows [][]string

	paginator := elasticloadbalancingv2.NewDescribeTargetGroupsPaginator(c.elbv2, &elasticloadbalancingv2.DescribeTargetGroupsInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, tg := range page.TargetGroups {
			name := aws.ToString(tg.TargetGroupName)
			if !containsAny(name, "k8s", p.prefix) {
				continue
			}
			rows = append(rows, []string{
				name,
				string(tg.Protocol),
				fmt.Sprintf("%d", aws.ToInt32(tg.Port)),
				aws.ToString(tg.VpcId),
			})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkNatGateways(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"NatGatewayId", "State", "VpcId", "SubnetId"}
	var rows [][]string

	paginator := ec2.NewDescribeNatGatewaysPaginator(c.ec2, &ec2.DescribeNatGatewaysInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, nat := range page.NatGateways {
			if nat.State == ec2types.NatGatewayStateDeleted {
				continue
			}
			rows = append(rows, []string{
				aws.ToString(nat.NatGatewayId),
				string(nat.State),
				aws.ToString(nat.VpcId),
				aws.ToString(nat.SubnetId),
			})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkElasticIPs(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"AllocationId", "PublicIp", "AssociationId", "NetworkInterfaceId"}
	out, err := c.ec2.DescribeAddresses(ctx, &ec2.DescribeAddressesInput{})
	if err != nil {
		return checkResult{headers: headers, err: err}
	}
	var rows [][]string
	for _, a := range out.Addresses {
		rows = append(rows, []string{
			aws.ToString(a.AllocationId),
			aws.ToString(a.PublicIp),
			aws.ToString(a.AssociationId),
			aws.ToString(a.NetworkInterfaceId),
		})
	}
	return checkResult{headers: headers, rows: rows}
}

func checkNetworkInterfaces(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"NetworkInterfaceId", "Status", "Description", "InstanceId", "VpcId"}
	var rows [][]string

	paginator := ec2.NewDescribeNetworkInterfacesPaginator(c.ec2, &ec2.DescribeNetworkInterfacesInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, eni := range page.NetworkInterfaces {
			desc := aws.ToString(eni.Description)
			if !containsAny(desc, "ELB", "eks", p.prefix) {
				continue
			}
			instanceID := ""
			if eni.Attachment != nil {
				instanceID = aws.ToString(eni.Attachment.InstanceId)
			}
			rows = append(rows, []string{
				aws.ToString(eni.NetworkInterfaceId),
				string(eni.Status),
				desc,
				instanceID,
				aws.ToString(eni.VpcId),
			})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkSecurityGroups(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"GroupId", "GroupName", "VpcId"}
	var rows [][]string

	paginator := ec2.NewDescribeSecurityGroupsPaginator(c.ec2, &ec2.DescribeSecurityGroupsInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, sg := range page.SecurityGroups {
			name := aws.ToString(sg.GroupName)
			if name == "default" {
				continue
			}
			if !containsAny(name, "k8s", p.prefix) {
				continue
			}
			rows = append(rows, []string{aws.ToString(sg.GroupId), name, aws.ToString(sg.VpcId)})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkInternetGateways(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"InternetGatewayId", "VpcId"}
	var rows [][]string

	paginator := ec2.NewDescribeInternetGatewaysPaginator(c.ec2, &ec2.DescribeInternetGatewaysInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, igw := range page.InternetGateways {
			vpcID := ""
			if len(igw.Attachments) > 0 {
				vpcID = aws.ToString(igw.Attachments[0].VpcId)
			}
			rows = append(rows, []string{aws.ToString(igw.InternetGatewayId), vpcID})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkDynamoDBTables(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"TableName"}
	var rows [][]string

	paginator := dynamodb.NewListTablesPaginator(c.ddb, &dynamodb.ListTablesInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, name := range page.TableNames {
			if strings.Contains(name, "terraform-locks") {
				continue
			}
			if !containsAny(name, p.prefix, "expense") {
				continue
			}
			rows = append(rows, []string{name})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkECRRepositories(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"RepositoryName", "RepositoryUri"}
	var rows [][]string

	paginator := ecr.NewDescribeRepositoriesPaginator(c.ecr, &ecr.DescribeRepositoriesInput{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, repo := range page.Repositories {
			name := aws.ToString(repo.RepositoryName)
			if !containsAny(name, p.prefix, "expense") {
				continue
			}
			rows = append(rows, []string{name, aws.ToString(repo.RepositoryUri)})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkContainerInsightsLogGroups(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"LogGroupName", "RetentionInDays"}
	var rows [][]string

	prefix := fmt.Sprintf("/aws/containerinsights/%s", p.clusterName)
	paginator := cloudwatchlogs.NewDescribeLogGroupsPaginator(c.logs, &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: aws.String(prefix),
	})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, lg := range page.LogGroups {
			retention := "-"
			if lg.RetentionInDays != nil {
				retention = fmt.Sprintf("%d", *lg.RetentionInDays)
			}
			rows = append(rows, []string{aws.ToString(lg.LogGroupName), retention})
		}
	}
	return checkResult{headers: headers, rows: rows}
}

func checkSSMParameters(ctx context.Context, c *awsClients, p params) checkResult {
	headers := []string{"Name"}
	var rows [][]string

	path := fmt.Sprintf("/%s/expense", p.prefix)
	paginator := ssm.NewGetParametersByPathPaginator(c.ssm, &ssm.GetParametersByPathInput{
		Path:      aws.String(path),
		Recursive: aws.Bool(true),
	})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return checkResult{headers: headers, err: err}
		}
		for _, param := range page.Parameters {
			rows = append(rows, []string{aws.ToString(param.Name)})
		}
	}
	return checkResult{headers: headers, rows: rows}
}
