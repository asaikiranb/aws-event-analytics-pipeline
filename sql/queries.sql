-- Query 1: Conversion Funnel
-- For each product, calculate view -> add_to_cart -> purchase conversion rates
SELECT 
    product_id,
    category,
    views,
    add_to_cart,
    purchases,
    ROUND(view_to_cart_rate * 100, 2) as view_to_cart_pct,
    ROUND(cart_to_purchase_rate * 100, 2) as cart_to_purchase_pct,
    ROUND(view_to_purchase_rate * 100, 2) as view_to_purchase_pct
FROM capstone_gold_annangi.conversion_funnel
WHERE views > 0
ORDER BY purchases DESC, views DESC
LIMIT 20
;

-- Query 2: Hourly Revenue
-- Total revenue by hour (price × quantity for purchases)
SELECT 
    event_datetime as hour,
    ROUND(total_revenue, 2) as revenue,
    purchase_count as num_purchases
FROM capstone_gold_annangi.hourly_revenue
ORDER BY event_datetime
;

-- Query 3: Top 10 Products
-- Most frequently viewed products with view counts
SELECT 
    product_id,
    category,
    view_count
FROM capstone_gold_annangi.product_views
ORDER BY view_count DESC
LIMIT 10
;

-- Query 4: Category Performance
-- Daily event counts (all types) grouped by category
SELECT 
    event_date,
    category,
    event_type,
    event_count
FROM capstone_gold_annangi.category_performance
ORDER BY event_date DESC, category, event_count DESC
;

-- Query 5: User Activity
-- Count of unique users and sessions per day
SELECT 
    event_date,
    unique_users,
    unique_sessions,
    total_events,
    ROUND(CAST(total_events AS DOUBLE) / CAST(unique_users AS DOUBLE), 2) as events_per_user,
    ROUND(CAST(total_events AS DOUBLE) / CAST(unique_sessions AS DOUBLE), 2) as events_per_session
FROM capstone_gold_annangi.user_activity
ORDER BY event_date DESC
;