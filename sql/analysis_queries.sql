-- 1. How many customers has Foodie-Fi ever had?

SELECT COUNT(DISTINCT customer_id) AS total_number_of_customers
FROM subscriptions;

-- 2. What is the monthly distribution of trial plan start_date values 
--    for our dataset - use the start of the month as the group by value

SELECT month(start_date), count(*) AS total_monthly_count
FROM subscriptions
WHERE plan_id = 0
GROUP BY month(start_date)
ORDER BY month(start_date);

-- 3. What plan start_date values occur after the year 2020 for our dataset? 
--       Show the breakdown by count of events for each plan_name

SELECT p.plan_name, count(p.plan_name) AS total
FROM subscriptions s
inner JOIN plans p
ON s.plan_id = p.plan_id
WHERE s.start_date > '2020-12-31'
GROUP BY p.plan_name
ORDER BY total;

-- 4. What is the customer count and percentage of customers 
--     who have churned rounded to 1 decimal place?

SELECT count(DISTINCT customer_id) AS total_churn,
round((count(DISTINCT customer_id)*100.0) / (SELECT count(DISTINCT customer_id) FROM subscriptions), 1)
AS churn_percentage
FROM subscriptions
WHERE plan_id = 4;

-- 5. How many customers have churned straight after their initial free
-- trial - what percentage is this rounded to the nearest whole number?

WITH next_plan AS (
SELECT customer_id,
plan_id,
lead(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_plan_id
FROM subscriptions
)
SELECT count(customer_id) AS churned_after_trial,
round((count(customer_id) * 100.0) / (SELECT count(DISTINCT customer_id) FROM subscriptions),0)
AS percentage_of_total
FROM next_plan
WHERE plan_id = 0
AND next_plan_id = 4;

-- 6. What is the number and percentage of customer plans after their initial free trial?

WITH next_plan_check AS (
SELECT customer_id,
plan_id,
lead(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_plan_ID
FROM subscriptions
)
SELECT p.plan_name,
COUNT(n.customer_id) AS customer_count,
    ROUND(
        (COUNT(n.customer_id) * 100.0) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 
        1
    ) AS percentage
FROM next_plan_check as n
JOIN plans p
ON n.next_plan_ID = p.plan_id
WHERE n.plan_id = 0
GROUP BY p.plan_name, n.plan_id
ORDER BY p.plan_id;

-- 7. What is the customer count and percentage breakdown of all 5 plan_name values at 2020-12-31?

WITH latest_plan_2020 AS (
SELECT customer_id,
plan_id,
start_date,
ROW_NUMBER() OVER (
PARTITION BY customer_id
ORDER BY start_date DESC)
AS plan_rank
FROM subscriptions
WHERE start_date <= '2020-12-31'
)
SELECT
p.plan_name,
count(l.customer_id) AS customer_count,
ROUND((COUNT(l.customer_id) * 100.0) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 1)
AS percentage
FROM latest_plan_2020 l
JOIN plans p
ON l.plan_id = p.plan_id
WHERE l.plan_rank = 1
GROUP BY p.plan_name, l.plan_id
ORDER BY l.plan_id;

-- 8. How many customers have upgraded to an annual plan in 2020?

SELECT COUNT(*) AS total_annual
FROM subscriptions
WHERE plan_id = 3
  AND start_date >= '2020-01-01' 
  AND start_date <= '2020-12-31';

-- 9.How many days on average does it take for a customer to an annual plan from 
--         the day they join Foodie-Fi?

WITH join_date AS (
    SELECT
        customer_id,
        start_date AS join_date
    FROM subscriptions
    WHERE plan_id = 0
),
annual_date AS (
    SELECT
        customer_id,
        start_date AS annual_date
    FROM subscriptions
    WHERE plan_id = 3
)
SELECT AVG(DATEDIFF(a.annual_date, j.join_date)) AS avg_days
FROM join_date j
JOIN annual_date a
    ON j.customer_id = a.customer_id;

-- 10. Can you further breakdown this average value into 30 day periods
--     (i.e. 0-30 days, 31-60 days etc)

WITH join_date AS (
    SELECT
        customer_id,
        start_date AS join_date
    FROM subscriptions
    WHERE plan_id = 0
),
annual_date AS (
    SELECT
        customer_id,
        start_date AS annual_date
    FROM subscriptions
    WHERE plan_id = 3
),
annual_days AS (
SELECT j.customer_id,
datediff(a.annual_date, j.join_date) AS days_to_annual
FROM join_date j
JOIN annual_date a
ON j.customer_id = a.customer_id
)
SELECT floor(days_to_annual / 30) AS bucket,
count(*) AS total_customers
FROM annual_days
GROUP BY floor(days_to_annual / 30)
ORDER BY bucket;

-- 11. How many customers downgraded from a pro monthly to a basic monthly plan in 2020?

WITH plan_changes AS (
SELECT
customer_id,
plan_id,
start_date,
lead(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_plan_id,
lead(start_date) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_start_date
FROM subscriptions
)
SELECT count(DISTINCT customer_id) AS downgraded_customers
FROM plan_changes
WHERE plan_id = 2
AND next_plan_id = 1
AND year(next_start_date) = 2020;


--  C. Challenge Payment Question

WITH RECURSIVE payment_table AS (
SELECT
s.customer_id,
s.plan_id,
s.start_date AS payment_date,
lead(s.start_date) over(PARTITION BY s.customer_id ORDER BY s.start_date) AS next_plan_date,
CASE
WHEN plan_id = 1 THEN 9.90
WHEN plan_id = 2 THEN 19.90
WHEN plan_id = 3 THEN 199.00
else 0
end AS amount
FROM subscriptions s
WHERE s.plan_id != 0 AND s.plan_id != 4
AND s.start_date <= '2020-12-31'

UNION ALL

select
customer_id,
plan_id,
date_add(payment_date, INTERVAL 1 month) AS payment_date,
next_plan_date,
amount
FROM payment_table
WHERE plan_id IN (1,2)
AND date_add(payment_date, INTERVAL 1 month) < COALESCE(next_plan_date, '2021-01-01')
AND date_add(payment_date, INTERVAL 1 month) <= '2021-12-31'
)

SELECT 
customer_id,
plan_id,
payment_date,
amount
FROM payment_table
order BY customer_id, payment_date;


-- Outside The Box Questions

-- Different ways to measure growth of the services

-- 1. growth based on net paid subscribers

WITH monthly_paying_users AS (
SELECT
DATE_FORMAT(start_date, '%Y-%m-01') AS payment_month,
count(DISTINCT customer_id) AS active_paid_subscribers
FROM subscriptions
WHERE plan_id not IN (0,4)
GROUP BY 1),
growth_calculation AS (
SELECT
payment_month,
active_paid_subscribers,
lag(active_paid_subscribers) OVER (ORDER BY payment_month) AS prev_month_subscribers
FROM monthly_paying_users)
SELECT payment_month,
active_paid_subscribers,
prev_month_subscribers,
round(((active_paid_subscribers - prev_month_subscribers) / prev_month_subscribers) * 100,
2) AS subscriber_growth_rate_percentage
FROM growth_calculation;

-- 2. based on monthly churn rate

WITH monthly_status AS (
SELECT
DATE_FORMAT(start_date, '%Y-%m-01') AS activity_month,
count(DISTINCT CASE WHEN plan_id != 0 THEN customer_id end) AS total_active_customers,
count(DISTINCT CASE WHEN plan_id = 4 THEN customer_id end) AS churned_customers
FROM subscriptions
GROUP BY 1
)
SELECT activity_month,
total_active_customers,
churned_customers,
round((churned_customers / total_active_customers) * 100, 2) AS monthly_churn_rate_percentage
FROM monthly_status
ORDER BY activity_month;

-- What key metrics would you recommend Foodie-Fi management to track over time 
--    to assess performance of their overall business?

-- 1. again by customer churn rate

WITH monthly_status AS (
SELECT
DATE_FORMAT(start_date, '%Y-%m-01') AS activity_month,
count(DISTINCT CASE WHEN plan_id != 0 THEN customer_id end) AS total_active_customers,
count(DISTINCT CASE WHEN plan_id = 4 THEN customer_id end) AS churned_customers
FROM subscriptions
GROUP BY 1
)
SELECT activity_month,
total_active_customers,
churned_customers,
round((churned_customers / total_active_customers) * 100, 2) AS monthly_churn_rate_percentage
FROM monthly_status
WHERE total_active_customers > 0
ORDER BY activity_month;

-- 2. by LTV to CAC ratio

-- first find the average revenue per user
-- then customer lifetime value
-- calculate customer acquisition cost


WITH business_metrics as(
SELECT
count(DISTINCT CASE WHEN s.plan_id = 4 THEN customer_id end)/
count(DISTINCT CASE WHEN s.plan_id != 0 THEN customer_id end) AS churn_rate_decimal,
round(sum(p.price) / count(DISTINCT s.customer_id), 2) AS ARPU
FROM subscriptions s
JOIN plans p
ON s.plan_id = p.plan_id
),

ltv_calculation AS (
SELECT
round(ARPU, 2) AS average_revenue_per_user,
round(churn_rate_decimal * 100, 2) AS churn_date_percentage,
round(ARPU / churn_rate_decimal, 2) AS calculated_ltv
FROM business_metrics
),

marketing_cac AS (
SELECT 50.00 AS assumed_cac
)

SELECT
l.average_revenue_per_user AS ARPU,
l.churn_date_percentage churn_rate_pct,
l.calculated_ltv AS customer_lifetime_value,
m.assumed_cac AS customer_acquisition_cost,
round(l.calculated_ltv / m.assumed_cac, 2) AS ltv_to_cac_ratio
FROM ltv_calculation l
CROSS JOIN marketing_cac m;

-- What are some key customer journeys or experiences 
--  that you would analyse further to improve customer retention?

WITH monthly_starts AS (
SELECT
customer_id,
min(start_date) AS monthly_start_date
FROM subscriptions
WHERE plan_id in (1,2)
GROUP BY customer_id
),
annual_upgrades AS (
SELECT
customer_id,
start_date AS annual_start_date
FROM subscriptions
WHERE plan_id = 3
)
SELECT
count(m.customer_id) AS total_upgraded_customers,
round(avg(datediff(a.annual_start_date, m.monthly_start_date)), 0) AS avg_days_before_annual_upgrade,
min(DATEDIFF(a.annual_start_date, m.monthly_start_date)) AS fastest_upgrade_days,
max(DATEDIFF(a.annual_start_date, m.monthly_start_date)) AS slowest_upgrade_days
FROM monthly_starts m
JOIN annual_upgrades a
ON m.customer_id = a.customer_id;

-- Find out how fast monthly users upgrade to the Pro Annual plan ($199)

-- annual plan brings more than basic monthly in 19 months
-- if we knew how fast customers upgrade their plan to annual on average
-- we would be able to send emails on a sweet spot when regular users
-- are most likely to upgrade long-term


-- If the Foodie-Fi team were to create an exit survey shown to customers 
-- who wish to cancel their subscription, what questions would you include in the survey?


-- What is the main reason you are canceling today?

--  Price / Value

--  Content Selection

--  Technical Issues

--  Product Usability

--  Temporary Need:


-- How long have you felt this way about the platform?

--  Just within the last week

--  For about a month

--  For several months / since I started using it
