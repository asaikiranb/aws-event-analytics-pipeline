# Building a Production-Grade Event Analytics Pipeline

**Author**: Sai Kiran Babu Annangi  
**Date**: December 2025  
**Project**: E-Commerce Event Analytics Pipeline

---

## The Problem

I had a real-world scenario to solve: data scientists at an e-commerce company couldn't query their event logs. The product team had been logging everything (page views, cart additions, purchases), but the data was stuck in raw JSON files. Nobody could get answers to basic questions like "which products convert best?" or "what's our hourly revenue?"

My job was to build a pipeline that transforms 500,000 to 750,000 events arriving every 5 minutes into something actually usable. And it had to keep working without manual intervention.

## How It Works

![Pipeline Architecture](./pipeline_architecture_diagram_1764840103912.png)

I built this using a three-layer approach: Bronze, Silver, and Gold.

First, an EventBridge scheduler triggers a Lambda function every 5 minutes. The Lambda generates events and writes them to S3 as compressed JSON files with Hive partitioning. That's the Bronze layer - raw data exactly as it arrives.

Next, a Glue ETL job reads new events from Bronze, cleans them up, and writes them to the Silver layer as Parquet files. The job only processes new data using Glue's bookmark feature, so I never reprocess the same events twice.

Finally, I create five pre-aggregated tables in the Gold layer. These tables answer specific business questions instantly, without scanning millions of raw events.

Athena sits on top of everything, letting analysts run SQL queries against any layer.

## Why Three Layers?

I looked at simpler options first.

I could have gone straight from raw data to aggregated tables. But then what happens when someone asks a new question? I'd have to reprocess everything from scratch. Debugging would be painful because I couldn't see the intermediate cleaned data.

I could have created just the Silver layer and stopped there. Analysts could query it directly. But they'd be writing complex GROUP BY queries constantly, and Athena would scan gigabytes of data for simple questions. That gets expensive fast.

Three layers solved both problems. Bronze gives me the raw data if I ever need to reprocess. Silver gives me clean data for unexpected questions. Gold gives me instant answers to common questions.

The storage cost is minimal. I'm paying maybe an extra dollar per month to store the same data three times. The benefits are huge.

## Handling Incremental Data

This was the trickiest requirement. New events arrive every 5 minutes. If I reprocess everything each time, the job would eventually take longer than 5 minutes to run. At scale, that's a disaster.

I used Glue job bookmarks to track which data I've already processed. Here's how it works: the Bronze layer uses Hive partitioning like `events/year=2025/month=12/day=04/hour=09/minute=15/`. When my job runs, Glue remembers the last partition it processed. Next time, it only reads new partitions.

In my code, I enable this with one parameter:

```python
datasource = glueContext.create_dynamic_frame.from_catalog(
    database=source_db,
    table_name=source_table,
    transformation_ctx="datasource"
)
```

That `transformation_ctx` parameter tells Glue to track what I've processed. It's simple, but it completely changes how the pipeline scales.

I tested it by running the job twice. First run processed all the data. Second run processed nothing because there was no new data. Perfect.

## Why Parquet?

For the Silver layer, I needed something that would make queries cheap and fast. Parquet was the obvious choice.

Parquet is columnar storage. When you query for just the `user_id` and `revenue` columns, Athena only reads those columns from disk. With JSON, Athena has to read and parse every single record, even if you only need two fields.

I saw this play out in testing. The same query on JSON data scanned 2GB. On Parquet, it scanned 200MB. That's a 10x difference in cost.

Parquet also compresses better than JSON and lets Athena skip entire file chunks based on min/max statistics. These aren't theoretical benefits. They show up immediately in your AWS bill.

## Partitioning Strategy

I partitioned the Silver layer by date: `year/month/day`. Not by hour or minute like Bronze. Here's why.

Too many partitions creates overhead. The Glue catalog has to track metadata for every partition. With hourly partitions, I'd have 24 partitions per day. With 5-minute partitions, I'd have 288. That's a lot of metadata.

Most queries ask for data by day or longer periods anyway. "Show me yesterday's revenue" or "compare this week to last week." Daily partitions handle these perfectly. A query for one day scans one partition instead of hundreds.

It's a balance. You want enough partitions to avoid scanning unnecessary data, but not so many that the metadata becomes a problem.

## Pre-Aggregating Common Queries

I had five specific business questions to answer:

1. Product conversion funnels (views to cart to purchase)
2. Hourly revenue
3. Most viewed products
4. Daily category performance
5. Daily user activity

I could force analysts to write GROUP BY queries against Silver for each of these. Or I could create dedicated tables that already have the answers.

Look at the conversion funnel query. Without pre-aggregation:

```sql
SELECT product_id,
       SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) as views,
       SUM(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) as carts
FROM silver.events
GROUP BY product_id
```

This scans millions of events and does all the counting at query time.

With a Gold table:

```sql
SELECT product_id, views, add_to_cart, purchases
FROM gold.conversion_funnel
ORDER BY purchases DESC
```

The Gold table might have 30 rows (one per product). The query completes in under a second and costs almost nothing.

The downside? Gold tables only answer specific questions. If someone asks something new, they have to go back to Silver. That's fine. Most queries are repeats. Pre-aggregating the common ones saves time and money.

## Infrastructure as Code

I extended the CloudFormation template to include everything the pipeline needs.

I added three S3 buckets: one for source events, one for processed data (Bronze/Silver/Gold), and one for scripts. I created three Glue databases with catalog tables pointing to the right S3 locations. I defined two Glue ETL jobs with job bookmarks enabled. I set up an Athena workgroup for queries.

CloudFormation lets me deploy the exact same infrastructure to any AWS account. The entire pipeline is code. If something breaks, I can recreate it in minutes. If I need a dev environment, I deploy the template with different parameters.

I made it reusable with parameters:

```yaml
Parameters:
  StudentId:
    Type: String

Resources:
  ProcessedDataBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub 'capstone-processed-${StudentId}-${AWS::AccountId}'
```

Change the `StudentId` parameter and everything gets unique names. No conflicts.

## The ETL Code

My Bronze-to-Silver script does the critical transformation work.

It reads from the Bronze catalog using job bookmarks. It parses the timestamp field from an ISO 8601 string to a proper timestamp type. It derives new columns: `event_date`, `event_hour`, and `revenue` (calculated as price times quantity for purchases). It writes everything to Parquet, partitioned by year, month, and day.

Here's the core logic:

```python
df_cleaned = df.withColumn(
    "timestamp_parsed",
    F.to_timestamp(F.col("timestamp"))
).withColumn(
    "event_date",
    F.to_date(F.col("timestamp_parsed"))
).withColumn(
    "revenue",
    F.when(
        F.col("event_type") == "purchase",
        F.col("price") * F.col("quantity")
    ).otherwise(0.0)
)

df_cleaned.write \
    .mode("append") \
    .partitionBy("year", "month", "day") \
    .parquet(target_path)
```

For the Gold layer, I created the aggregation tables using Athena CTAS queries. I could have used a Glue job, but Athena was simpler and more efficient for one-time aggregations.

## Cost Optimization

I thought about cost from the start.

Parquet cuts Athena scan costs by 80-90% compared to JSON. Partitioning means queries only scan the data they need. Gold tables are tiny, so querying them costs almost nothing. Lifecycle policies automatically delete old data after 30-90 days.

For the data I processed (about 10 million events), the costs look like this:

S3 storage is about 2 cents per month for all three layers. The Glue jobs cost 15 cents total to run. Each query against Gold costs less than a penny.

The real win is in repeated queries. If 10 people run the same revenue query against raw data, that's 10x the cost. If they query the Gold table, the cost is negligible.

## Problems I Ran Into

Partition discovery was my first issue. After the Glue job finished, I couldn't see the new partitions in Athena. I had to add a repair statement to scan S3 and register them with the catalog. Small thing, but it took me a while to figure out.

I also had to verify job bookmarks were working. I ran the Bronze-to-Silver job twice and checked CloudWatch Logs. First run: "Processing 693,149 events." Second run: "No new data to process." That confirmed it was tracking state correctly.

Null handling in Parquet could have been tricky, but it turned out fine. The `search_query` field is null for non-search events, and `product_id` is null for searches. Parquet handled it because I kept the types consistent.

## Testing and Validation

I tested everything before calling it done.

I ran the incremental processing test (job ran twice, processed data once). I manually checked a few Parquet files to verify the schema looked right. I ran all five analytical queries and eyeballed the results to make sure they made sense. I compared query times between Silver and Gold to confirm Gold was faster.

Gold queries finished in 1-2 seconds. The same queries against Silver took 15-20 seconds. That's the difference pre-aggregation makes.

## What I Learned

Pre-aggregate the queries you run often, but keep the raw data around for everything else. You can't predict every question, so you need both.

Incremental processing isn't optional at scale. Reprocessing everything every time will eventually break your pipeline.

Partitioning is about finding the right balance. Too few partitions and queries scan too much data. Too many and metadata becomes a problem.

Cost and performance are linked. Parquet and pre-aggregation make queries both faster and cheaper.

Infrastructure as code saves time. I can rebuild this entire pipeline in five minutes.

## Final Thoughts

If someone asks me in an interview to walk them through a data pipeline I built, this is the one. It shows I can design infrastructure, write ETL code, optimize for cost and performance, and make trade-offs between different approaches.

This pipeline handles 10 million events per hour today. It could handle 100 million or a billion with the same architecture. That's what production-ready means.

---

## Technical Specifications

**Data Volume**: 500K-750K events every 5 minutes (~10M events/hour)  
**Data Format**: Bronze (JSONL.GZ) to Silver (Parquet) to Gold (Parquet)  
**Partitioning**: Bronze (year/month/day/hour/minute), Silver/Gold (year/month/day)  
**Incremental Processing**: AWS Glue Job Bookmarks  
**Query Engine**: AWS Athena  
**Infrastructure**: AWS CloudFormation  
**Processing Engine**: PySpark on AWS Glue 4.0  

**Key S3 URIs**:
- Bronze: `s3://capstone-events-annangi-655945924787/events/`
- Silver: `s3://capstone-processed-annangi-655945924787/silver/events/`
- Gold: `s3://capstone-processed-annangi-655945924787/gold/`
- Scripts: `s3://capstone-scripts-annangi-655945924787/scripts/`
- Queries: `s3://capstone-scripts-annangi-655945924787/queries/queries.sql`

---

*This pipeline was built as part of a data engineering capstone project, simulating real-world production requirements for an e-commerce analytics platform.*
