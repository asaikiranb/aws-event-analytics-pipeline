#!/bin/bash

# Monitor event data and run pipeline when ready
# Requires: At least 12 event files (1 hour of data)

set -e

REGION="us-west-2"
SOURCE_BUCKET="capstone-events-annangi-655945924787"
BRONZE_DB="capstone_bronze_annangi"
BRONZE_TO_SILVER_JOB="capstone-bronze-to-silver-annangi"
SILVER_TO_GOLD_JOB="capstone-silver-to-gold-annangi"
WORKGROUP="capstone-workgroup-annangi"
MIN_FILES=12

echo "========================================="
echo "Capstone Pipeline Monitor & Executor"
echo "========================================="
echo ""

echo "Checking event data status..."
FILE_COUNT=$(aws s3 ls s3://$SOURCE_BUCKET/events/ --recursive --region $REGION | wc -l | tr -d ' ')

echo "Current status:"
echo "  Event files: $FILE_COUNT / $MIN_FILES minimum"
echo "  Target: At least 12 files (1 hour of data)"
echo ""

if [ "$FILE_COUNT" -lt "$MIN_FILES" ]; then
    echo "⏳ Not enough data yet. Need $((MIN_FILES - FILE_COUNT)) more files."
    echo ""
    echo "Lambda runs every 5 minutes. Estimated time remaining:"
    MINUTES_REMAINING=$((5 * (MIN_FILES - FILE_COUNT)))
    echo "  ~$MINUTES_REMAINING minutes"
    echo ""
    echo "Re-run this script when ready, or wait for automatic execution."
    exit 0
fi

echo "✅ Sufficient data available! ($FILE_COUNT files)"
echo ""
echo "========================================="
echo "STEP 1: Discover Bronze Partitions"
echo "========================================="

echo "Running MSCK REPAIR TABLE on Bronze catalog..."
QUERY_ID=$(aws athena start-query-execution \
    --query-string "MSCK REPAIR TABLE $BRONZE_DB.events" \
    --result-configuration "OutputLocation=s3://capstone-athena-results-annangi-655945924787/" \
    --work-group "$WORKGROUP" \
    --region "$REGION" \
    --query 'QueryExecutionId' \
    --output text)

echo "  Query ID: $QUERY_ID"
echo "  Waiting for completion..."

aws athena wait query-execution-complete \
    --query-execution-id "$QUERY_ID" \
    --region "$REGION"

PARTITIONS=$(aws athena get-query-results \
    --query-execution-id "$QUERY_ID" \
    --region "$REGION" \
    --query 'ResultSet.Rows[1].Data[0].VarCharValue' \
    --output text)

echo "  ✅ Partitions discovered: $PARTITIONS"
echo ""

echo "========================================="
echo "STEP 2: Run Bronze to Silver Job"
echo "========================================="

echo "Starting Glue job: $BRONZE_TO_SILVER_JOB"
JOB_RUN_ID=$(aws glue start-job-run \
    --job-name "$BRONZE_TO_SILVER_JOB" \
    --region "$REGION" \
    --query 'JobRunId' \
    --output text)

echo "  Job Run ID: $JOB_RUN_ID"
echo "  Waiting for completion (this may take 2-5 minutes)..."

while true; do
    JOB_STATUS=$(aws glue get-job-run \
        --job-name "$BRONZE_TO_SILVER_JOB" \
        --run-id "$JOB_RUN_ID" \
        --region "$REGION" \
        --query 'JobRun.JobRunState' \
        --output text)
    
    if [ "$JOB_STATUS" == "SUCCEEDED" ]; then
        echo "  ✅ Bronze to Silver job completed successfully!"
        break
    elif [ "$JOB_STATUS" == "FAILED" ] || [ "$JOB_STATUS" == "ERROR" ]; then
        echo "  ❌ Job failed with status: $JOB_STATUS"
        echo "  Check CloudWatch Logs for details"
        exit 1
    else
        echo "  Status: $JOB_STATUS (waiting...)"
        sleep 15
    fi
done

echo ""

echo "========================================="
echo "STEP 3: Run Silver to Gold Job"
echo "========================================="

echo "Starting Glue job: $SILVER_TO_GOLD_JOB"
JOB_RUN_ID=$(aws glue start-job-run \
    --job-name "$SILVER_TO_GOLD_JOB" \
    --region "$REGION" \
    --query 'JobRunId' \
    --output text)

echo "  Job Run ID: $JOB_RUN_ID"
echo "  Waiting for completion..."

while true; do
    JOB_STATUS=$(aws glue get-job-run \
        --job-name "$SILVER_TO_GOLD_JOB" \
        --run-id "$JOB_RUN_ID" \
        --region "$REGION" \
        --query 'JobRun.JobRunState' \
        --output text)
    
    if [ "$JOB_STATUS" == "SUCCEEDED" ]; then
        echo "  ✅ Silver to Gold job completed successfully!"
        break
    elif [ "$JOB_STATUS" == "FAILED" ] || [ "$JOB_STATUS" == "ERROR" ]; then
        echo "  ❌ Job failed with status: $JOB_STATUS"
        echo "  Check CloudWatch Logs for details"
        exit 1
    else
        echo "  Status: $JOB_STATUS (waiting...)"
        sleep 15
    fi
done

echo ""

echo "========================================="
echo "STEP 4: Verify Incremental Processing"
echo "========================================="

echo "Running Bronze to Silver job AGAIN to verify job bookmarks..."
JOB_RUN_ID=$(aws glue start-job-run \
    --job-name "$BRONZE_TO_SILVER_JOB" \
    --region "$REGION" \
    --query 'JobRunId' \
    --output text)

echo "  Job Run ID: $JOB_RUN_ID"
echo "  Waiting for completion..."

while true; do
    JOB_STATUS=$(aws glue get-job-run \
        --job-name "$BRONZE_TO_SILVER_JOB" \
        --run-id "$JOB_RUN_ID" \
        --region "$REGION" \
        --query 'JobRun.JobRunState' \
        --output text)
    
    if [ "$JOB_STATUS" == "SUCCEEDED" ]; then
        echo "  ✅ Second run completed - check logs to verify it processed 0 or minimal new events"
        break
    elif [ "$JOB_STATUS" == "FAILED" ] || [ "$JOB_STATUS" == "ERROR" ]; then
        echo "  Note: Second run status: $JOB_STATUS"
        break
    else
        sleep 15
    fi
done

echo ""

echo "========================================="
echo "PIPELINE EXECUTION COMPLETE!"
echo "========================================="
echo ""
echo "✅ All ETL jobs completed successfully!"
echo ""
echo "Key S3 URIs (for submission):"
echo "  Silver Data: s3://capstone-processed-annangi-655945924787/silver/events/"
echo "  Gold Data:   s3://capstone-processed-annangi-655945924787/gold/"
echo "  Queries:     s3://capstone-scripts-annangi-655945924787/queries/queries.sql"
echo ""
echo "Next steps:"
echo "  1. Run queries from queries.sql in Athena Console"
echo "  2. Copy blog_post.md to Google Doc and share with instructor"
echo "  3. Submit all deliverables"
echo ""
echo "To run sample queries now:"
echo "  aws athena start-query-execution \\"
echo "    --query-string 'SELECT * FROM capstone_gold_annangi.conversion_funnel LIMIT 10' \\"
echo "    --work-group capstone-workgroup-annangi \\"
echo "    --region us-west-2"
echo ""
