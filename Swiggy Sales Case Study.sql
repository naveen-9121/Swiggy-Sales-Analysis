CREATE DATABASE IF NOT EXISTS swiggy_analysis;
USE swiggy_analysis;


-- RAW DATA TABLE
CREATE TABLE swiggy_data (
    state VARCHAR(100),
    city VARCHAR(100),
    order_date DATE,
    restaurant_name VARCHAR(200),
    location VARCHAR(200),
    category VARCHAR(100),
    dish_name VARCHAR(150),
    price_inr DECIMAL(10,2),
    rating DECIMAL(3,2),
    rating_count INT
);

-- DATA CLEANING & VALIDATION
	-- NULL CHECK
    
SELECT
    SUM(state IS NULL) AS null_state,
    SUM(city IS NULL) AS null_city,
    SUM(order_date IS NULL) AS null_order_date,
    SUM(restaurant_name IS NULL) AS null_restaurant,
    SUM(location IS NULL) AS null_location,
    SUM(category IS NULL) AS null_category,
    SUM(dish_name IS NULL) AS null_dish,
    SUM(price_inr IS NULL) AS null_price,
    SUM(rating IS NULL) AS null_rating,
    SUM(rating_count IS NULL) AS null_rating_count
FROM swiggy_data;
    
-- BLANK / EMPTY STRING CHECK
SELECT *
FROM swiggy_data
WHERE
TRIM(state) = ''
OR TRIM(city) = ''
OR TRIM(restaurant_name) = ''
OR TRIM(location) = ''
OR TRIM(category) = ''
OR TRIM(dish_name) = '';

-- DUPLICATE DETECTION
SELECT
    state, city, order_date, restaurant_name,
    location, category, dish_name,
    price_inr, rating, rating_count,
    COUNT(*) AS cnt
FROM swiggy_data
GROUP BY
    state, city, order_date, restaurant_name,
    location, category, dish_name,
    price_inr, rating, rating_count
HAVING COUNT(*) > 1;

-- DUPLICATE REMOVAL
CREATE TABLE swiggy_data_clean AS
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY
                   state, city, order_date, restaurant_name,
                   location, category, dish_name,
                   price_inr, rating, rating_count
               ORDER BY order_date
           ) AS rn
    FROM swiggy_data
) t
WHERE rn = 1;

-- DIMENSIONAL MODELLING
	-- DATE DIMENSION


CREATE TABLE dim_date (
    date_id INT AUTO_INCREMENT PRIMARY KEY,
    full_date DATE,
    year INT,
    month INT,
    month_name VARCHAR(20),
    quarter INT,
    week INT
);
INSERT INTO dim_date
(
    full_date,
    year,
    month,
    month_name,
    quarter,
    week
)
SELECT DISTINCT
    order_date,
    YEAR(order_date),
    MONTH(order_date),
    MONTHNAME(order_date),
    QUARTER(order_date),
    WEEK(order_date)
FROM swiggy_data_clean
WHERE order_date IS NOT NULL;

-- LOCATION DIMENSION

CREATE TABLE dim_location (
    location_id INT AUTO_INCREMENT PRIMARY KEY,
    state VARCHAR(100),
    city VARCHAR(100),
    location VARCHAR(200)
);

INSERT INTO dim_location
(
    state,
    city,
    location
)
SELECT DISTINCT
    state,
    city,
    location
FROM swiggy_data_clean
WHERE state IS NOT NULL
  AND city IS NOT NULL
  AND location IS NOT NULL;
  
 -- RESTAURANT DIMENSION 
CREATE TABLE dim_restaurant (
    restaurant_id INT AUTO_INCREMENT PRIMARY KEY,
    restaurant_name VARCHAR(200)
);

INSERT INTO dim_restaurant
(
    restaurant_name
)
SELECT DISTINCT
    restaurant_name
FROM swiggy_data_clean
WHERE restaurant_name IS NOT NULL;

-- CATEGORY DIMENSION
CREATE TABLE dim_category (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    category VARCHAR(100)
);

INSERT INTO dim_category (category)
SELECT DISTINCT category
FROM swiggy_data_clean
WHERE category IS NOT NULL;

-- DISH DIMENSION
CREATE TABLE dim_dish (
    dish_id INT AUTO_INCREMENT PRIMARY KEY,
    dish_name VARCHAR(150)
);
INSERT INTO dim_dish (dish_name)
SELECT DISTINCT dish_name
FROM swiggy_data_clean
WHERE dish_name IS NOT NULL;

-- FACT TABLE 

CREATE TABLE fact_swiggy_orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    price_inr DECIMAL(10,2),
    rating DECIMAL(3,2),
    rating_count INT,
    date_id INT,
    location_id INT,
    restaurant_id INT,
    category_id INT,
    dish_id INT
);

-- Insertin fact table
INSERT INTO fact_swiggy_orders (
    price_inr,
    rating,
    rating_count,
    date_id,
    location_id,
    restaurant_id,
    category_id,
    dish_id
)
SELECT
    s.price_inr,
    s.rating,
    s.rating_count,
    d.date_id,
    l.location_id,
    r.restaurant_id,
    c.category_id,
    di.dish_id
FROM swiggy_data_clean s
JOIN dim_date d
    ON s.order_date = d.full_date
JOIN dim_location l
    ON s.state = l.state
   AND s.city = l.city
   AND s.location = l.location
JOIN dim_restaurant r
    ON s.restaurant_name = r.restaurant_name
JOIN dim_category c
    ON s.category = c.category
JOIN dim_dish di
    ON s.dish_name = di.dish_name;
    
    -- KPI DEVELOPMENT
    
    -- Total Orders
SELECT COUNT(*) AS total_orders FROM fact_swiggy_orders;

-- Total Revenue (INR Million)
SELECT ROUND(SUM(price_inr)/1000000, 2) AS revenue_inr_million
FROM fact_swiggy_orders;

-- Average Dish Price
SELECT ROUND(AVG(price_inr), 2) AS avg_dish_price
FROM fact_swiggy_orders;

-- Average Rating
SELECT ROUND(AVG(rating), 2) AS avg_rating
FROM fact_swiggy_orders;


-- DEEP-DIVE BUSINESS ANALYSIS
	-- Monthly Order Trend
    
SELECT
    d.year,
    d.month_name,
    COUNT(*) AS total_orders
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;
    
-- Quarterly Trend
SELECT
    d.year,
    d.quarter,
    COUNT(*) AS total_orders
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.year, d.quarter
ORDER BY d.year, d.quarter;

-- Orders by Day of Week

SELECT
    DAYNAME(d.full_date) AS day_name,
    COUNT(*) AS total_orders
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY DAYNAME(d.full_date), DAYOFWEEK(d.full_date)
ORDER BY DAYOFWEEK(d.full_date);


-- Top 10 Cities by Orders
SELECT
    l.city,
    COUNT(*) AS total_orders
FROM fact_swiggy_orders f
JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.city
ORDER BY total_orders DESC
LIMIT 10;


-- Revenue by State
SELECT
    l.state,
    ROUND(SUM(f.price_inr),2) AS revenue
FROM fact_swiggy_orders f
JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.state;

-- Customer Spend Buckets

SELECT
    CASE
        WHEN price_inr < 100 THEN 'Under 100'
        WHEN price_inr BETWEEN 100 AND 199 THEN '100–199'
        WHEN price_inr BETWEEN 200 AND 299 THEN '200–299'
        WHEN price_inr BETWEEN 300 AND 499 THEN '300–499'
        ELSE '500+'
    END AS spend_bucket,
    COUNT(*) AS total_orders
FROM fact_swiggy_orders
GROUP BY spend_bucket;





