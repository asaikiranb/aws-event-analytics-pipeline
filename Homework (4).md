# Capstone Project: Production-Ready Event Analytics Pipeline

## Overview

Build a production-grade analytics pipeline for high-volume e-commerce event data. You'll receive a CloudFormation template that generates 500K-750K events every 5 minutes, extend it with your pipeline infrastructure, and deliver working queries and a portfolio-quality blog post.

**This is your opportunity to demonstrate end-to-end data engineering skills in a realistic scenario you can discuss confidently in job interviews.**

---

## What You'll Build

### Business Context

You're a data engineer at an e-commerce company. The product analytics team has been logging user events, but data scientists can't effectively query the raw logs. Your job: build a production-grade analytics pipeline that transforms raw events into a reliable, performant dataset they can use for experiments and analysis.

### Technical Requirements

1. **Extend the provided CloudFormation template** to include your pipeline infrastructure (Glue jobs, databases, output buckets, etc.)
2. **Handle incremental data** - new events arrive every 5 minutes; your pipeline must process new data without reprocessing everything
3. **Support the 5 required queries** - your analytical dataset must make these queries possible and performant

---

## Source Data

### Lambda Behavior

- Runs every 5 minutes via EventBridge
- Each execution writes one gzipped JSON Lines file to S3
- Files use **Hive-style partitioning** for automatic Glue/Athena partition discovery:
  ```
  events/year=YYYY/month=MM/day=DD/hour=HH/minute=mm/events-{timestamp}.jsonl.gz
  ```
- **Each file contains 500,000-750,000 events** (randomized)
- **Minimum for grading: 1 hour of data**

### Event Schema

Single event type with these fields:
- `timestamp` - ISO 8601 string, always present
- `user_id` - string, always present
- `session_id` - string, always present
- `event_type` - enum: "page_view", "add_to_cart", "remove_from_cart", "purchase", "search"
- `product_id` - string, present for view/cart/purchase, null for search
- `quantity` - integer, present for cart/purchase, null otherwise
- `price` - decimal, present for cart/purchase, null otherwise
- `category` - string, present for view/cart/purchase, null for search
- `search_query` - string, present only for search events, null otherwise

**Example event:**
```json
{"timestamp":"2025-11-18T14:23:45.123Z","user_id":"u_89234","session_id":"s_29384","event_type":"add_to_cart","product_id":"p_5521","quantity":2,"price":29.99,"category":"electronics","search_query":null}
```

---

## The 5 Required Queries

Your analytical dataset must enable the business to attempt to understand the following:

1. **Conversion Funnel**: For each product, calculate view → add_to_cart → purchase conversion rates
2. **Hourly Revenue**: Total revenue by hour (price × quantity for purchases)
3. **Top 10 Products**: Most frequently viewed products with view counts
4. **Category Performance**: Daily event counts (all types) grouped by category
5. **User Activity**: Count of unique users and sessions per day

---

## Deliverables

Submit these items:

1. **Extended CloudFormation template** - Your `capstone-starter.cfn.yaml` with your pipeline resources added
2. **SQL/Code that Builds Pipelines** Either idempotent `build_pipeline.ipynb` notebook or AWS Glue ETL Script
   - Similar to prior labs, this is the piece of code that can be run multiple times to build/maintain your pipeline
   - Does not need to be deployed via CloudFormation
3. **S3 URI of analytical dataset** - Where your final, query-ready data lives
4. **S3 URI of queries file** - A `queries.sql` file containing SQL for the 5 required queries
   - Include inline comments indicating which query is for what question
   - Include all five statements in a single file separated by semicolons, example:

    ```sql
    -- query 1, conversion funnel
    select * from dual
    ;
    -- query 2, hourly revenue
    select * from dual
    ;
    -- [... and so on ...]
    ```


5. **Google Doc link** - Your blog post (1500-2500 words, shared with instructor)
   - Enable "comment access" so that feedback can be provided
   - Ensure sharing is enabled or else you won't be awarded points for the written portion of this assignment

---

## Grading

### Code (50%)

Instructor will:
1. Deploy your CloudFormation template
2. Review code and validate data is not being reprocessed
   - Looking for use of bookmarks, using Athena's pseudo columns, etc.
   - Will be reviewed alongside your narrative to understand your design choice.
3. Execute your 5 SQL queries

### Blog Post (50%)

Your blog post must include:
- **Architecture diagram** - Clear visual of pipeline flow
  - You are free to use whatever drawing solution you know
  - You are required to embed your drawing as an image in the Google doc file
- **Design rationale**  - Alternatives considered, choices justified
- **Technical accuracy** - Correct understanding of tools
- **Communication quality** - Portfolio-ready writing

Think of this as interview prep: "Walk me through a data pipeline you built."

---

## Getting Started

### Step 1: Deploy Starter Template

```bash
aws cloudformation create-stack \
  --stack-name capstone-{your-UW-alias} \
  --template-body file://capstone-starter.cfn.yaml \
  --parameters ParameterKey=StudentId,ParameterValue={your-UW-alias} \
  --region us-west-2

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name capstone-{your-UW-alias} \
  --region us-west-2
```

### Step 2: Explore Sample Data

Sample data is provided in the repo, but a script is also provided in case you want to generate more.

```bash
# Generate local sample files for exploration
python generate_sample_data.py --num-files 6 --events-per-file 1000

# Examine the data
gunzip -c sample-data/events-*.jsonl.gz | head -20
```

### Step 3: Design Your Pipeline

Consider:
- Bronze/Silver/Gold layer architecture
- Partitioning strategy for incremental processing
- File format (JSON, Parquet, etc..)
- Cost considerations
- Complexity considerations

### Step 4: Extend CloudFormation Template

Add your resources to `capstone-starter.cfn.yaml`, could include:
- Glue databases/tables
- Glue ETL jobs or crawlers
- Athena workgroups
- Output S3 buckets
- Any other infrastructure needed

### Step 5: Validate Queries

Test each query against your resultant dataset

### Step 6: Write Blog Post

Document your journey:
- What problem you solved
- How you designed your solution
- Why you made specific choices
- How you validated it works

---

## Helpful Hints

- **Start small**: Test with 1 hour of data (the grading requirement) before scaling
- **Partition wisely**: Many events per write means partitioning matters
- **Consider costs**: Athena charges by data scanned - design accordingly
- **Incremental ETL**: Review Week 9 strategies for handling new data
- **Test early**: Don't wait until the last minute to verify queries work
- **Document decisions**: Your blog post should explain trade-offs

---

## Common Pitfalls

- **Processing all data every time** - Use incremental ETL strategies
- **No partitioning** - Query performance will suffer at scale
- **Wrong file format** - Consider compression and columnar formats
- **Hardcoded values** - Use CloudFormation parameters and outputs
- **Skipping validation** - Test queries before submission
- **Generic blog post** - Show YOUR specific decisions and reasoning

---

## Resources

- **Week 9 Labs**: Incremental ETL patterns with Glue/Spark
- **AWS Glue Documentation**: [https://docs.aws.amazon.com/glue/](https://docs.aws.amazon.com/glue/)
- **Athena Best Practices**: [https://docs.aws.amazon.com/athena/latest/ug/performance-tuning.html](https://docs.aws.amazon.com/athena/latest/ug/performance-tuning.html)
- **Grading Queries**: See `grading/queries.sql` for exact SQL

---