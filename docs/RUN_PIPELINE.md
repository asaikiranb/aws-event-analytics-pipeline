# Quick Reference: Running the Pipeline

## Current Status
- ✅ Infrastructure deployed
- ✅ ETL scripts uploaded to S3
- ✅ Queries uploaded to S3
- ⏳ Waiting for 1 hour of event data (Lambda runs every 5 minutes)

## When Data is Ready (after ~1 hour from 01:15 AM)

### Step 1: Discover Bronze Partitions
```bash
aws glue start-crawler --name bronze-events-crawler --region us-west-2
# OR manually add partitions:
aws athena start-query-execution \
  --query-string "MSCK REPAIR TABLE capstone_bronze_annangi.events" \
  --result-configuration OutputLocation=s3://capstone-athena-results-annangi-655945924787/ \
  --workgroup capstone-workgroup-annangi \
  --region us-west-2
```

### Step 2: Run Bronze to Silver Job
```bash
aws glue start-job-run \
  --job-name capstone-bronze-to-silver-annangi \
  --region us-west-2
```

Monitor the job:
```bash
aws glue get-job-runs \
  --job-name capstone-bronze-to-silver-annangi \
  --region us-west-2 \
  --query 'JobRuns[0].[JobRunState,ExecutionTime,ErrorMessage]' \
  --output table
```

### Step 3: Run Silver to Gold Job
```bash
aws glue start-job-run \
  --job-name capstone-silver-to-gold-annangi \
  --region us-west-2
```

### Step 4: Query Gold Tables in Athena
```bash
# Query 1: Conversion Funnel
aws athena start-query-execution \
  --query-string "$(cat queries.sql | grep -A 10 'Query 1')" \
  --result-configuration OutputLocation=s3://capstone-athena-results-annangi-655945924787/ \
  --workgroup capstone-workgroup-annangi \
  --region us-west-2
```

Or use Athena Console:
1. Navigate to Athena in AWS Console
2. Select workgroup: `capstone-workgroup-annangi`
3. Database: `capstone_gold_annangi`
4. Run queries from `queries.sql`

### Step 5: Verify Incremental Processing
Run Bronze-to-Silver job AGAIN and verify it processes 0 or minimal new events:
```bash
aws glue start-job-run \
  --job-name capstone-bronze-to-silver-annangi \
  --region us-west-2
```

Check CloudWatch Logs to confirm: "No new data to process" or very few events.

## Checking Event Data Status

Check how many event files we have:
```bash
aws s3 ls s3://capstone-events-annangi-655945924787/events/ \
  --recursive --region us-west-2 | wc -l
```

Check total data size:
```bash
aws s3 ls s3://capstone-events-annangi-655945924787/events/ \
  --recursive --region us-west-2 --summarize | grep "Total Size"
```

List recent files (should see Hive partitioning):
```bash
aws s3 ls s3://capstone-events-annangi-655945924787/events/ \
  --recursive --region us-west-2 | tail -10
```

## Expected Timeline

| Time | Lambda Runs | Total Events | Ready? |
|------|-------------|--------------|--------|
| 01:15 | 1 | ~700K | No (need 1 hour) |
| 01:20 | 2 | ~1.4M | No |
| 01:30 | 3 | ~2.1M | No |
| 01:45 | 4 | ~2.8M | No |
| 02:00 | 5 | ~3.5M | No |
| 02:15 | 13+ | ~9M+ | ✅ YES |

Target: At least 12 files (1 hour of data per homework requirements)

## Troubleshooting

### If Glue job fails:
```bash
# Check CloudWatch Logs
aws logs tail /aws-glue/jobs/error --follow --region us-west-2
aws logs tail /aws-glue/jobs/output --follow --region us-west-2
```

### If no partitions appear in Bronze:
```bash
# Manually repair table
aws athena start-query-execution \
  --query-string "MSCK REPAIR TABLE capstone_bronze_annangi.events" \
  --result-configuration OutputLocation=s3://capstone-athena-results-annangi-655945924787/ \
  --region us-west-2
```

### If job bookmark doesn't work:
Reset bookmark (only if needed):
```bash
aws glue reset-job-bookmark \
  --job-name capstone-bronze-to-silver-annangi \
  --region us-west-2
```

## Final Deliverables Checklist

- [x] Extended CloudFormation template: `Capstone Starter.yaml`
- [x] ETL scripts: `bronze_to_silver.py`, `silver_to_gold.py` (in S3)
- [ ] S3 URI of analytical dataset: `s3://capstone-processed-annangi-655945924787/gold/`
- [x] S3 URI of queries: `s3://capstone-scripts-annangi-655945924787/queries/queries.sql`
- [ ] Google Doc blog post (copy from `blog_post.md` and share with instructor)
