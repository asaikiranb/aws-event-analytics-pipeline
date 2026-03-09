import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.window import Window

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

print(f"Starting Silver to Gold transformation")
print(f"Source: {args['SOURCE_DATABASE']}.{args['SOURCE_TABLE']}")
print(f"Target: s3://{args['TARGET_BUCKET']}/gold/")

source_db = args['SOURCE_DATABASE']
source_table = args['SOURCE_TABLE']
target_bucket = args['TARGET_BUCKET']
target_db = args['TARGET_DATABASE']

df = spark.table(f"{source_db}.{source_table}")

if df.count() == 0:
    print("No data in Silver layer")
    job.commit()
    sys.exit(0)

print(f"Processing {df.count():,} events from Silver layer")

print("Creating Gold table 1: Conversion Funnel")
conversion_funnel = df.filter(
    F.col("event_type").isin("page_view", "add_to_cart", "purchase")
).groupBy("product_id", "category").agg(
    F.sum(F.when(F.col("event_type") == "page_view", 1).otherwise(0)).alias("views"),
    F.sum(F.when(F.col("event_type") == "add_to_cart", 1).otherwise(0)).alias("add_to_cart"),
    F.sum(F.when(F.col("event_type") == "purchase", 1).otherwise(0)).alias("purchases")
).withColumn(
    "view_to_cart_rate",
    F.when(F.col("views") > 0, F.col("add_to_cart") / F.col("views")).otherwise(0)
).withColumn(
    "cart_to_purchase_rate",
    F.when(F.col("add_to_cart") > 0, F.col("purchases") / F.col("add_to_cart")).otherwise(0)
).withColumn(
    "view_to_purchase_rate",
    F.when(F.col("views") > 0, F.col("purchases") / F.col("views")).otherwise(0)
)

funnel_path = f"s3://{target_bucket}/gold/conversion_funnel/"
conversion_funnel.write.mode("overwrite").parquet(funnel_path)
print(f"Wrote {conversion_funnel.count():,} rows to conversion_funnel")

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS {target_db}.conversion_funnel (
        product_id STRING,
        category STRING,
        views BIGINT,
        add_to_cart BIGINT,
        purchases BIGINT,
        view_to_cart_rate DOUBLE,
        cart_to_purchase_rate DOUBLE,
        view_to_purchase_rate DOUBLE
    )
    STORED AS PARQUET
    LOCATION '{funnel_path}'
""")
spark.sql(f"MSCK REPAIR TABLE {target_db}.conversion_funnel")

print("Creating Gold table 2: Hourly Revenue")
hourly_revenue = df.filter(
    F.col("event_type") == "purchase"
).withColumn(
    "event_datetime",
    F.date_format(F.col("timestamp_parsed"), "yyyy-MM-dd HH:00:00")
).groupBy("event_datetime").agg(
    F.sum("revenue").alias("total_revenue"),
    F.count("*").alias("purchase_count")
).orderBy("event_datetime")

revenue_path = f"s3://{target_bucket}/gold/hourly_revenue/"
hourly_revenue.write.mode("overwrite").parquet(revenue_path)
print(f"Wrote {hourly_revenue.count():,} rows to hourly_revenue")

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS {target_db}.hourly_revenue (
        event_datetime STRING,
        total_revenue DOUBLE,
        purchase_count BIGINT
    )
    STORED AS PARQUET
    LOCATION '{revenue_path}'
""")
spark.sql(f"MSCK REPAIR TABLE {target_db}.hourly_revenue")

print("Creating Gold table 3: Product Views")
product_views = df.filter(
    F.col("event_type") == "page_view"
).groupBy("product_id", "category").agg(
    F.count("*").alias("view_count")
).orderBy(F.desc("view_count"))

views_path = f"s3://{target_bucket}/gold/product_views/"
product_views.write.mode("overwrite").parquet(views_path)
print(f"Wrote {product_views.count():,} rows to product_views")

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS {target_db}.product_views (
        product_id STRING,
        category STRING,
        view_count BIGINT
    )
    STORED AS PARQUET
    LOCATION '{views_path}'
""")
spark.sql(f"MSCK REPAIR TABLE {target_db}.product_views")

print("Creating Gold table 4: Category Performance")
category_performance = df.groupBy("event_date", "category", "event_type").agg(
    F.count("*").alias("event_count")
).orderBy("event_date", "category", "event_type")

category_path = f"s3://{target_bucket}/gold/category_performance/"
category_performance.write.mode("overwrite").parquet(category_path)
print(f"Wrote {category_performance.count():,} rows to category_performance")

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS {target_db}.category_performance (
        event_date DATE,
        category STRING,
        event_type STRING,
        event_count BIGINT
    )
    STORED AS PARQUET
    LOCATION '{category_path}'
""")
spark.sql(f"MSCK REPAIR TABLE {target_db}.category_performance")

print("Creating Gold table 5: User Activity")
user_activity = df.groupBy("event_date").agg(
    F.countDistinct("user_id").alias("unique_users"),
    F.countDistinct("session_id").alias("unique_sessions"),
    F.count("*").alias("total_events")
).orderBy("event_date")

activity_path = f"s3://{target_bucket}/gold/user_activity/"
user_activity.write.mode("overwrite").parquet(activity_path)
print(f"Wrote {user_activity.count():,} rows to user_activity")

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS {target_db}.user_activity (
        event_date DATE,
        unique_users BIGINT,
        unique_sessions BIGINT,
        total_events BIGINT
    )
    STORED AS PARQUET
    LOCATION '{activity_path}'
""")
spark.sql(f"MSCK REPAIR TABLE {target_db}.user_activity")

job.commit()
print("Silver to Gold job completed successfully")
print("Created 5 analytical tables in Gold layer")
