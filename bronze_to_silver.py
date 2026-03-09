import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import TimestampType, DateType
from datetime import datetime

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'SOURCE_DATABASE',
    'SOURCE_TABLE',
    'TARGET_BUCKET',
    'TARGET_DATABASE'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

print(f"Starting Bronze to Silver transformation")
print(f"Source: {args['SOURCE_DATABASE']}.{args['SOURCE_TABLE']}")
print(f"Target: s3://{args['TARGET_BUCKET']}/silver/events/")

source_db = args['SOURCE_DATABASE']
source_table = args['SOURCE_TABLE']
target_bucket = args['TARGET_BUCKET']
target_db = args['TARGET_DATABASE']
target_path = f"s3://{target_bucket}/silver/events/"

datasource = glueContext.create_dynamic_frame.from_catalog(
    database=source_db,
    table_name=source_table,
    transformation_ctx="datasource",
    push_down_predicate="year >= '2025'"
)

if datasource.count() == 0:
    print("No new data to process")
    job.commit()
    sys.exit(0)

df = datasource.toDF()
print(f"Processing {df.count():,} events")

df_cleaned = df.withColumn(
    "timestamp_parsed",
    F.to_timestamp(F.col("timestamp"))
).withColumn(
    "event_date",
    F.to_date(F.col("timestamp_parsed"))
).withColumn(
    "event_hour",
    F.hour(F.col("timestamp_parsed"))
).withColumn(
    "revenue",
    F.when(
        F.col("event_type") == "purchase",
        F.col("price") * F.col("quantity")
    ).otherwise(0.0)
).withColumn(
    "year",
    F.year(F.col("event_date"))
).withColumn(
    "month",
    F.month(F.col("event_date"))
).withColumn(
    "day",
    F.dayofmonth(F.col("event_date"))
).select(
    "timestamp",
    "timestamp_parsed",
    "event_date",
    "event_hour",
    "user_id",
    "session_id",
    "event_type",
    "product_id",
    "quantity",
    "price",
    "revenue",
    "category",
    "search_query",
    "year",
    "month",
    "day"
)

print("Writing to Silver layer as Parquet with date partitioning")
event_count = df_cleaned.count()
df_cleaned.write \
    .mode("append") \
    .partitionBy("year", "month", "day") \
    .parquet(target_path)

print(f"Successfully wrote {event_count:,} events to Silver layer")
print(f"Data written to: {target_path}")
print("Note: Run MSCK REPAIR TABLE in Athena to discover partitions")

job.commit()
print("Bronze to Silver job completed successfully")