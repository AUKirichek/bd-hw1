-- Запросы

-- 1
SELECT product_id,
       ROUND(AVG(item_list_price_at_sale), 2) AS avg_sale_price
FROM hw1.order_items
GROUP BY product_id
ORDER BY AVG(item_list_price_at_sale) DESC NULLS LAST, product_id
LIMIT 5;

-- 2
SELECT p.brand,
       SUM(oi.item_list_price_at_sale * oi.quantity) AS total_order_value
FROM hw1.order_items AS oi
JOIN hw1.products AS p ON p.product_id = oi.product_id
GROUP BY p.brand
ORDER BY total_order_value DESC NULLS LAST, p.brand;

-- 3
SELECT EXTRACT(YEAR FROM order_date)::integer AS order_year,
       EXTRACT(MONTH FROM order_date)::integer AS order_month,
       COUNT(*) AS order_count
FROM hw1.orders
GROUP BY EXTRACT(YEAR FROM order_date), EXTRACT(MONTH FROM order_date)
ORDER BY order_year, order_month;

-- 4
WITH max_cost_by_line AS (
    SELECT product_line, MAX(standard_cost) AS max_cost
    FROM hw1.products
    GROUP BY product_line
)
SELECT p.product_id, p.product_line, p.standard_cost
FROM hw1.products AS p
JOIN max_cost_by_line AS m
    ON p.product_line = m.product_line
   AND p.standard_cost = m.max_cost
ORDER BY p.product_line, p.product_id;

-- 5
WITH order_totals AS (
    SELECT order_id,
           SUM(item_list_price_at_sale * quantity) AS order_total
    FROM hw1.order_items
    GROUP BY order_id
)
SELECT o.order_status,
       COUNT(*) AS order_count,
       SUM(COALESCE(ot.order_total, 0)) AS total_order_value
FROM hw1.orders AS o
LEFT JOIN order_totals AS ot ON ot.order_id = o.order_id
GROUP BY o.order_status
ORDER BY o.order_status;

-- 6
SELECT c.customer_id, c.last_name, c.first_name
FROM hw1.customers AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM hw1.orders AS o
    WHERE o.customer_id = c.customer_id
)
ORDER BY c.customer_id;

-- 7
WITH state_limits AS (
    SELECT state,
           MIN(property_valuation) AS min_valuation,
           MAX(property_valuation) AS max_valuation
    FROM hw1.customers
    GROUP BY state
)
SELECT c.state, c.property_valuation, c.last_name, c.first_name
FROM hw1.customers AS c
JOIN state_limits AS s ON c.state = s.state
WHERE c.property_valuation = s.min_valuation
   OR c.property_valuation = s.max_valuation
ORDER BY c.state, c.property_valuation, c.customer_id;

-- 8
SELECT o.customer_id,
       MIN(p.product_line) AS product_line,
       COUNT(DISTINCT o.order_id) AS order_count
FROM hw1.orders AS o
JOIN hw1.order_items AS oi ON oi.order_id = o.order_id
JOIN hw1.products AS p ON p.product_id = oi.product_id
GROUP BY o.customer_id
HAVING COUNT(DISTINCT p.product_line) = 1
ORDER BY o.customer_id;

-- 9
WITH category_counts AS (
    SELECT p.product_class,
           COUNT(DISTINCT o.order_id) AS total_orders,
           COUNT(DISTINCT o.order_id)
               FILTER (WHERE o.order_status = 'Cancelled') AS cancelled_orders
    FROM hw1.products AS p
    LEFT JOIN hw1.order_items AS oi ON oi.product_id = p.product_id
    LEFT JOIN hw1.orders AS o ON o.order_id = oi.order_id
    GROUP BY p.product_class
)
SELECT product_class, total_orders, cancelled_orders,
       ROUND(100.0 * cancelled_orders / NULLIF(total_orders, 0), 2)
           AS cancelled_percent
FROM category_counts
ORDER BY product_class;

-- 10
WITH customer_order_counts AS (
    SELECT c.customer_id, COUNT(o.order_id) AS order_count
    FROM hw1.customers AS c
    LEFT JOIN hw1.orders AS o ON o.customer_id = c.customer_id
    GROUP BY c.customer_id
)
SELECT CASE
           WHEN order_count > 10 THEN 'High'
           WHEN order_count BETWEEN 5 AND 10 THEN 'Medium'
           ELSE 'Low'
       END AS segment,
       COUNT(*) AS customer_count
FROM customer_order_counts
GROUP BY segment
ORDER BY segment;

-- 11
WITH order_intervals AS (
    SELECT customer_id,
           order_date - LAG(order_date) OVER (
               PARTITION BY customer_id
               ORDER BY order_date, order_id
           ) AS order_gap
    FROM hw1.orders
), max_intervals AS (
    SELECT customer_id,
           MAX(order_gap) AS max_gap
    FROM order_intervals
    GROUP BY customer_id
    HAVING COUNT(*) > 1
)
SELECT c.first_name,
       c.last_name,
       c.job_title,
       ROUND(EXTRACT(EPOCH FROM m.max_gap) / 86400.0, 2) AS max_gap_days
FROM max_intervals AS m
JOIN hw1.customers AS c ON c.customer_id = m.customer_id
ORDER BY m.max_gap DESC, c.customer_id;

-- проверка после нормализации
SELECT current_database();

-- все пять таблиц, уникальные ключи, NULL и дубли.
WITH counts AS (
    SELECT 'states' AS table_name, COUNT(*) AS row_count,
           COUNT(state) AS nonnull_keys, COUNT(DISTINCT state) AS unique_keys
    FROM hw1.states
    UNION ALL
    SELECT 'customers', COUNT(*), COUNT(customer_id), COUNT(DISTINCT customer_id)
    FROM hw1.customers
    UNION ALL
    SELECT 'products', COUNT(*), COUNT(product_id), COUNT(DISTINCT product_id)
    FROM hw1.products
    UNION ALL
    SELECT 'orders', COUNT(*), COUNT(order_id), COUNT(DISTINCT order_id)
    FROM hw1.orders
    UNION ALL
    SELECT 'order_items', COUNT(*), COUNT(order_item_id), COUNT(DISTINCT order_item_id)
    FROM hw1.order_items
)
SELECT table_name, row_count, unique_keys,
       row_count - nonnull_keys AS null_keys,
       nonnull_keys - unique_keys AS duplicate_key_rows
FROM counts
ORDER BY table_name;



-- создание бд
/*
BEGIN;

CREATE SCHEMA hw1;

CREATE TABLE hw1.customers (
    customer_id integer PRIMARY KEY,
    first_name text NOT NULL,
    last_name text NOT NULL,
    gender text,
    dob date,
    job_title text,
    job_industry_category text,
    wealth_segment text,
    deceased_indicator boolean,
    owns_car boolean,
    address text,
    postcode text,
    state text NOT NULL,
    country text NOT NULL,
    property_valuation numeric(8,2) CHECK (property_valuation >= 0)
);

CREATE TABLE hw1.products (
    product_id integer PRIMARY KEY,
    brand text NOT NULL,
    product_line text NOT NULL,
    product_class text NOT NULL,
    product_size text,
    list_price numeric(12,2) NOT NULL CHECK (list_price >= 0),
    standard_cost numeric(12,2) NOT NULL CHECK (standard_cost >= 0)
);

CREATE TABLE hw1.orders (
    order_id integer PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES hw1.customers(customer_id),
    order_date timestamp without time zone NOT NULL,
    online_order boolean,
    order_status text NOT NULL
);

CREATE TABLE hw1.order_items (
    order_item_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES hw1.orders(order_id),
    product_id integer NOT NULL REFERENCES hw1.products(product_id),
    quantity integer NOT NULL CHECK (quantity > 0),
    item_list_price_at_sale numeric(12,2) NOT NULL
        CHECK (item_list_price_at_sale >= 0),
    item_standard_cost_at_sale numeric(12,2) NOT NULL
        CHECK (item_standard_cost_at_sale >= 0)
);

COMMIT;

*/


/*
BEGIN;


CREATE TABLE hw1.states (
    state text PRIMARY KEY,
    country text NOT NULL
);

INSERT INTO hw1.states (state, country)
SELECT DISTINCT state, country
FROM hw1.customers;

ALTER TABLE hw1.customers
    ADD CONSTRAINT customers_state_fkey
    FOREIGN KEY (state) REFERENCES hw1.states(state);

ALTER TABLE hw1.customers DROP COLUMN country;

COMMIT;
*/
