// check-destroy-eks is a Go rewrite of ../../check-destroy-eks.sh: a
// read-only post-destroy verification tool for the EKS runtime. It never
// calls a delete/terminate API — only Describe/List/Get calls.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strings"
	"sync"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ecr"
	"github.com/aws/aws-sdk-go-v2/service/eks"
	"github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

type params struct {
	region      string
	prefix      string
	clusterName string
}

type awsClients struct {
	eks   *eks.Client
	elbv2 *elasticloadbalancingv2.Client
	ec2   *ec2.Client
	ddb   *dynamodb.Client
	ecr   *ecr.Client
	logs  *cloudwatchlogs.Client
	ssm   *ssm.Client
}

// checkResult mirrors one "table" the bash version prints: a header row,
// zero or more data rows, or an error if the underlying AWS call failed.
type checkResult struct {
	headers []string
	rows    [][]string
	err     error
}

type checkFunc func(ctx context.Context, c *awsClients, p params) checkResult

func main() {
	region := flag.String("region", os.Getenv("AWS_REGION"), "AWS region (required)")
	prefix := flag.String("prefix", os.Getenv("PREFIX"), "Resource name prefix (required)")
	clusterName := flag.String("cluster-name", os.Getenv("EKS_CLUSTER_NAME"), "EKS cluster name (default: <prefix>-expense-eks)")
	flag.Parse()

	if *region == "" {
		fmt.Fprintln(os.Stderr, "ERROR: region is required (set --region or AWS_REGION).")
		os.Exit(1)
	}
	if *prefix == "" {
		fmt.Fprintln(os.Stderr, "ERROR: prefix is required (set --prefix or PREFIX).")
		os.Exit(1)
	}
	if *clusterName == "" {
		*clusterName = *prefix + "-expense-eks"
	}

	p := params{region: *region, prefix: *prefix, clusterName: *clusterName}

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(p.region))
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: loading AWS config: %v\n", err)
		os.Exit(1)
	}

	clients := &awsClients{
		eks:   eks.NewFromConfig(cfg),
		elbv2: elasticloadbalancingv2.NewFromConfig(cfg),
		ec2:   ec2.NewFromConfig(cfg),
		ddb:   dynamodb.NewFromConfig(cfg),
		ecr:   ecr.NewFromConfig(cfg),
		logs:  cloudwatchlogs.NewFromConfig(cfg),
		ssm:   ssm.NewFromConfig(cfg),
	}

	fmt.Printf("Region:       %s\n", p.region)
	fmt.Printf("Prefix:       %s\n", p.prefix)
	fmt.Printf("EKS cluster:  %s\n", p.clusterName)

	checks := []struct {
		name string
		fn   checkFunc
	}{
		{"EKS clusters", checkEKSClusters},
		{"EKS nodegroups (for expected cluster)", checkEKSNodegroups},
		{"EC2 instances tagged for this EKS cluster", checkEC2Instances},
		{"Load balancers matching prefix/k8s", checkLoadBalancers},
		{"Target groups matching prefix/k8s", checkTargetGroups},
		{"NAT gateways not deleted", checkNatGateways},
		{"Elastic IP addresses", checkElasticIPs},
		{"Network interfaces matching prefix/ELB/EKS", checkNetworkInterfaces},
		{"Non-default security groups matching prefix/k8s", checkSecurityGroups},
		{"Internet gateways", checkInternetGateways},
		{"DynamoDB tables (app stack)", checkDynamoDBTables},
		{"ECR repositories matching prefix/expense", checkECRRepositories},
		{"CloudWatch Container Insights log groups", checkContainerInsightsLogGroups},
		{"SSM parameters published for expenseapp CI", checkSSMParameters},
	}

	// All 13 checks are independent read-only AWS calls, so they run
	// concurrently instead of one-by-one like the bash version. `sem` is a
	// buffered channel used purely as a counting semaphore: it caps how many
	// checks are in flight at once (5) so we don't fire 13 API calls at the
	// same instant. Each goroutine writes to its own index of `results`, so
	// there's no shared-memory race even without a mutex -- and `i`/`fn` are
	// passed as arguments (not read from the loop variable) to avoid the
	// classic "closure captures the wrong iteration" bug.
	const maxConcurrent = 5
	sem := make(chan struct{}, maxConcurrent)
	results := make([]checkResult, len(checks))
	var wg sync.WaitGroup

	for i, chk := range checks {
		wg.Add(1)
		go func(i int, fn checkFunc) {
			defer wg.Done()
			sem <- struct{}{}        // acquire a slot
			defer func() { <-sem }() // release it when done
			results[i] = fn(ctx, clients, p)
		}(i, chk.fn)
	}
	wg.Wait()

	for i, chk := range checks {
		printResult(chk.name, results[i])
	}

	fmt.Println("\n==== Bootstrap (expected to survive destroy_apply) ====")
	fmt.Println("Remote state S3 bucket + DynamoDB state-lock table from backend.tf are not managed here.")
	fmt.Println("They should still exist after a successful destroy; only delete them manually if you intend to.")
	fmt.Println("\nDone. Review non-empty tables above as possible residue (bootstrap resources excluded from DynamoDB list).")
}

func printResult(name string, r checkResult) {
	fmt.Printf("\n==== %s ====\n", name)
	if r.err != nil {
		fmt.Printf("(command failed: %v; continuing)\n", r.err)
		return
	}
	if len(r.rows) == 0 {
		fmt.Println("(none)")
		return
	}

	widths := make([]int, len(r.headers))
	for i, h := range r.headers {
		widths[i] = len(h)
	}
	for _, row := range r.rows {
		for i, cell := range row {
			if len(cell) > widths[i] {
				widths[i] = len(cell)
			}
		}
	}

	printRow(r.headers, widths)
	for _, row := range r.rows {
		printRow(row, widths)
	}
}

func printRow(cells []string, widths []int) {
	parts := make([]string, len(cells))
	for i, cell := range cells {
		parts[i] = fmt.Sprintf("%-*s", widths[i], cell)
	}
	fmt.Println(strings.Join(parts, "  "))
}

// containsAny reports whether s contains any of the given substrings,
// skipping empty ones. It's the Go-side stand-in for the bash version's
// `contains(@, 'x') || contains(@, 'y')` JMESPath filters -- the AWS CLI's
// --query is applied client-side on the full JSON response, so the Go SDK
// (which returns that same JSON, already unmarshalled) needs the equivalent
// filtering written out explicitly instead of a query string.
func containsAny(s string, subs ...string) bool {
	for _, sub := range subs {
		if sub != "" && strings.Contains(s, sub) {
			return true
		}
	}
	return false
}
