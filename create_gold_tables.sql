-- Create Gold Layer Tables via Athena CTAS

-- Gold Table 1: Conversion Funnel
CREATE TABLE IF NOT EXISTS capstone_gold_annangi.conversion_funnel
WITH (
    format = 'PARQUET',
    external_location = 's3://capstone-processed-annangi-655945924787/gold/conversion_funnel/'
) AS
SELECT 
    product_id,
    category,
    SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) as views,
    SUM(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) as add_to_cart,
    SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) as purchases,
    CASE 
        WHEN SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) > 0 
        THEN CAST(SUM(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) AS DOUBLE) / CAST(SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) AS DOUBLE)
        ELSE 0.0
    END as view_to_cart_rate,
    CASE 
        WHEN SUM(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) > 0 
        THEN CAST(SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS DOUBLE) / CAST(SUM(CASE WHEN event_type = 'add_to_cart' THEN 1 ELSE 0 END) AS DOUBLE)
        ELSE 0.0
    END as cart_to_purchase_rate,
    CASE 
        WHEN SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) > 0 
        THEN CAST(SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS DOUBLE) / CAST(SUM(CASE WHEN event_type = 'page_view' THEN 1 ELSE 0 END) AS DOUBLE)
        ELSE 0.0
    END as view_to_purchase_rate
FROM capstone_silver_annangi.events
WHERE event_type IN ('page_view', 'add_to_cart', 'purchase')
GROUP BY product_id, category
;

-- Gold Table 2: Hourly Revenue
CREATE TABLE IF NOT EXISTS capstone_gold_annangi.hourly_revenue
WITH (
    format = 'PARQUET',
    external_location = 's3://capstone-processed-annangi-655945924787/gold/hourly_revenue/'
) AS
SELECT 
    DATE_FORMAT(timestamp_parsed, '%Y-%m-%d %H:00:00') as event_datetime,
    SUM(revenue) as total_revenue,
    COUNT(*) as purchase_count
FROM capstone_silver_annangi.events
WHERE event_type = 'purchase'
GROUP BY DATE_FORMAT(timestamp_parsed, '%Y-%m-%d %H:00:00')
ORDER BY event_datetime
;

-- Gold Table 3: Product Views
CREATE TABLE IF NOT EXISTS capstone_gold_annangi.product_views
WITH (
    format = 'PARQUET',
    external_location = 's3://capstone-processed-annangi-655945924787/gold/product_views/'
) AS
SELECT 
    product_id,
    category,
    COUNT(*) as view_count
FROM capstone_silver_annangi.events
WHERE event_type = 'page_view'
GROUP BY product_id, category
ORDER BY view_count DESC
;

-- Gold Table 4: Category Performance
CREATE TABLE IF NOT EXISTS capstone_gold_annangi.category_performance
WITH (
    format = 'PARQUET',
    external_location = 's3://capstone-processed-annangi-655945924787/gold/category_performance/'
) AS
SELECT 
    event_date,
    category,
    event_type,
    COUNT(*) as event_count
FROM capstone_silver_annangi.events
GROUP BY event_date, category, event_type
ORDER BY event_date DESC, category, event_type
;

-- Gold Table 5: User Activity
CREATE TABLE IF NOT EXISTS capstone_gold_annangi.user_activity
WITH (
    format = 'PARQUET',
    external_location = 's3://capstone-processed-annangi-655945924787/gold/user_activity/'
) AS
SELECT 
    event_date,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT session_id) as unique_sessions,
    COUNT(*) as total_events
FROM capstone_silver_annangi.events
GROUP BY event_date
ORDER BY event_date DESC
;