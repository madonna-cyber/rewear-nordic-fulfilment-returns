-- Rewear Nordic: SQL analysis (MySQL 8)
-- Run Rewear_MySQL_Import.sql first. Expected results are in the comments.

USE rewear_nordic;

-- Check: dispatched orders and late dispatch (expected 4818, 680, 14.1)
SELECT COUNT(Dispatched_At) AS dispatched,
       SUM(Dispatched_At > Promised_Dispatch_At) AS late,
       ROUND(100 * SUM(Dispatched_At > Promised_Dispatch_At) / COUNT(Dispatched_At), 1) AS late_pct
FROM fulfilment;


-- =========================================================
-- KEY QUESTION 1: Volume and dispatch by month and warehouse
-- =========================================================

-- Q1a. Orders and late dispatch % by month and warehouse (24 rows)
SELECT DATE_FORMAT(o.Order_Timestamp, '%Y-%m') AS order_month,
       f.Warehouse_ID,
       COUNT(*) AS dispatched_orders,
       SUM(f.Dispatched_At > f.Promised_Dispatch_At) AS late_dispatch,
       ROUND(100 * SUM(f.Dispatched_At > f.Promised_Dispatch_At) / COUNT(*), 1) AS late_pct
FROM orders o
JOIN fulfilment f ON f.Order_ID = o.Order_ID
WHERE f.Dispatched_At IS NOT NULL
GROUP BY order_month, f.Warehouse_ID
ORDER BY order_month, f.Warehouse_ID;

-- Q1b. Orders placed per day against daily capacity
-- Expected: Arlanda 364 days, 12 over capacity, busiest day 25. Moelndal 359 days, 14 over, busiest day 15.
WITH daily AS (
    SELECT f.Warehouse_ID, DATE(o.Order_Timestamp) AS order_day, COUNT(*) AS orders_that_day
    FROM orders o
    JOIN fulfilment f ON f.Order_ID = o.Order_ID
    WHERE o.Order_Status <> 'Cancelled'
    GROUP BY f.Warehouse_ID, DATE(o.Order_Timestamp)
)
SELECT w.Warehouse_Name, w.Daily_Order_Capacity,
       COUNT(*) AS days_with_orders,
       SUM(d.orders_that_day > w.Daily_Order_Capacity) AS days_over_capacity,
       MAX(d.orders_that_day) AS busiest_day
FROM daily d
JOIN warehouses w ON w.Warehouse_ID = d.Warehouse_ID
GROUP BY w.Warehouse_Name, w.Daily_Order_Capacity;


-- =========================================================
-- KEY QUESTION 2: Where do delays originate?
-- =========================================================

-- Q2a. Delay origin (delivered orders only)
-- Expected: On time 3698 (77.4%), late dispatch + late delivery 621 (13.0%),
-- carrier-only 406 (8.5%), late dispatch recovered in transit 52 (1.1%)
SELECT CASE
         WHEN Dispatched_At > Promised_Dispatch_At AND Delivered_At > Promised_Delivery_At THEN 'Late dispatch + late delivery'
         WHEN Dispatched_At > Promised_Dispatch_At AND Delivered_At <= Promised_Delivery_At THEN 'Late dispatch, recovered in transit'
         WHEN Dispatched_At <= Promised_Dispatch_At AND Delivered_At > Promised_Delivery_At THEN 'Carrier-only delay'
         ELSE 'On time'
       END AS delay_origin,
       COUNT(*) AS n_orders,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM fulfilment
WHERE Delivered_At IS NOT NULL AND Dispatched_At IS NOT NULL
GROUP BY delay_origin
ORDER BY n_orders DESC;

-- Q2b. Late delivery % by carrier
-- Expected: NordShip 26.6%, SveaParcel 19.2%, CityBox 19.1%
SELECT Carrier, COUNT(*) AS delivered,
       SUM(Delivered_At > Promised_Delivery_At) AS late,
       ROUND(100 * SUM(Delivered_At > Promised_Delivery_At) / COUNT(*), 1) AS late_pct
FROM fulfilment
WHERE Delivered_At IS NOT NULL
GROUP BY Carrier
ORDER BY late_pct DESC;

-- Q2c. Does a late dispatch lead to a late delivery?
-- Expected: Late dispatch 673 orders, 92.3%. On-time dispatch 4104 orders, 9.9%
SELECT CASE WHEN Dispatched_At > Promised_Dispatch_At THEN 'Late dispatch' ELSE 'On-time dispatch' END AS dispatch_status,
       COUNT(*) AS delivered,
       ROUND(100 * SUM(Delivered_At > Promised_Delivery_At) / COUNT(*), 1) AS late_delivery_pct
FROM fulfilment
WHERE Delivered_At IS NOT NULL
GROUP BY dispatch_status;


-- =========================================================
-- KEY QUESTION 3: Returns
-- =========================================================

-- Q3a. Return rate by category (completed orders)
-- Expected: Trousers 17.7%, Footwear 16.8%, Dresses 14.6%, Outerwear 9.1%, Bags 8.9%, Tops 8.2%, Accessories 7.7%
SELECT p.Category,
       COUNT(*) AS items_sold,
       COUNT(r.Return_ID) AS items_returned,
       ROUND(100 * COUNT(r.Return_ID) / COUNT(*), 1) AS return_rate_pct
FROM order_items oi
JOIN orders o ON o.Order_ID = oi.Order_ID
LEFT JOIN products p ON p.Product_ID = oi.Product_ID
LEFT JOIN product_returns r ON r.Order_Item_ID = oi.Order_Item_ID
WHERE o.Order_Status = 'Completed'
GROUP BY p.Category
ORDER BY return_rate_pct DESC;

-- Q3b. Return rate by item condition
-- Expected: Good 16.8%, Very good 11.2%, Like new 11.2%
SELECT p.Item_Condition,
       COUNT(*) AS items_sold,
       COUNT(r.Return_ID) AS items_returned,
       ROUND(100 * COUNT(r.Return_ID) / COUNT(*), 1) AS return_rate_pct
FROM order_items oi
JOIN orders o ON o.Order_ID = oi.Order_ID
LEFT JOIN products p ON p.Product_ID = oi.Product_ID
LEFT JOIN product_returns r ON r.Order_Item_ID = oi.Order_Item_ID
WHERE o.Order_Status = 'Completed'
GROUP BY p.Item_Condition
ORDER BY return_rate_pct DESC;

-- Q3c. Reasons customers gave
-- Expected: Fit or size 393 (36.3%), Changed mind 236, Not as described 176, Condition concern 146,
-- Arrived too late 66, Other 58, Not recorded 9
SELECT Return_Reason,
       COUNT(*) AS n_returns,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM product_returns
GROUP BY Return_Reason
ORDER BY n_returns DESC;

-- Q3d. Fit or size share of each category's returns
-- Expected: Trousers 45.8%, Footwear 42.3%, Dresses 40.9%, Tops 25.8%, Outerwear 22.3%, Accessories 22.0%, Bags 18.6%
SELECT p.Category,
       COUNT(*) AS n_returns,
       SUM(r.Return_Reason = 'Fit or size') AS fit_or_size,
       ROUND(100 * SUM(r.Return_Reason = 'Fit or size') / COUNT(*), 1) AS fit_pct
FROM product_returns r
JOIN order_items oi ON oi.Order_Item_ID = r.Order_Item_ID
LEFT JOIN products p ON p.Product_ID = oi.Product_ID
GROUP BY p.Category
ORDER BY fit_pct DESC;

-- Q3e. Condition-concern share of returns by item condition
-- Expected: Good 24.8%, Like new 11.6%, Very good 7.6%
SELECT p.Item_Condition,
       COUNT(*) AS n_returns,
       ROUND(100 * SUM(r.Return_Reason = 'Condition concern') / COUNT(*), 1) AS condition_concern_pct
FROM product_returns r
JOIN order_items oi ON oi.Order_Item_ID = r.Order_Item_ID
LEFT JOIN products p ON p.Product_ID = oi.Product_ID
GROUP BY p.Item_Condition;


-- =========================================================
-- KEY QUESTION 4: Costs
-- =========================================================

-- Q4a. Fulfilment cost by delivery service, split into components
-- Expected: Express total 93.39 (carrier 58.78), Standard total 71.61 (carrier 36.86)
SELECT o.Delivery_Service,
       COUNT(*) AS orders_shipped,
       ROUND(AVG(f.Handling_Cost_SEK), 2) AS avg_handling,
       ROUND(AVG(f.Packaging_Cost_SEK), 2) AS avg_packaging,
       ROUND(AVG(f.Carrier_Cost_SEK), 2) AS avg_carrier,
       ROUND(AVG(f.Handling_Cost_SEK + f.Packaging_Cost_SEK + f.Carrier_Cost_SEK), 2) AS avg_total
FROM orders o
JOIN fulfilment f ON f.Order_ID = o.Order_ID
WHERE f.Dispatched_At IS NOT NULL
GROUP BY o.Delivery_Service;

-- Q4b. Fulfilment cost by number of items in the order
-- Expected average cost: 1 item 66.72, 2 items 77.05, 3 items 86.51, 4 items 96.19 (24.05 per item)
WITH items AS (
    SELECT Order_ID, COUNT(*) AS items_in_order
    FROM order_items
    GROUP BY Order_ID
)
SELECT i.items_in_order,
       COUNT(*) AS orders_shipped,
       ROUND(AVG(f.Handling_Cost_SEK + f.Packaging_Cost_SEK + f.Carrier_Cost_SEK), 2) AS avg_cost,
       ROUND(AVG(f.Handling_Cost_SEK + f.Packaging_Cost_SEK + f.Carrier_Cost_SEK) / i.items_in_order, 2) AS avg_cost_per_item
FROM fulfilment f
JOIN items i ON i.Order_ID = f.Order_ID
WHERE f.Dispatched_At IS NOT NULL
GROUP BY i.items_in_order
ORDER BY i.items_in_order;

-- Q4c. Return costs and refunds by category
-- Expected: Trousers 310 returns, return cost 13001, refunds 73745. Outerwear refunds about 58100 from 103 returns
SELECT p.Category,
       COUNT(*) AS n_returns,
       ROUND(SUM(r.Return_Handling_Cost_SEK + r.Return_Carrier_Cost_SEK), 0) AS total_return_cost,
       ROUND(AVG(r.Return_Handling_Cost_SEK + r.Return_Carrier_Cost_SEK), 2) AS avg_return_cost,
       ROUND(SUM(r.Refund_Amount_SEK), 0) AS total_refunds
FROM product_returns r
LEFT JOIN order_items oi ON oi.Order_Item_ID = r.Order_Item_ID
LEFT JOIN products p ON p.Product_ID = oi.Product_ID
GROUP BY p.Category
ORDER BY total_return_cost DESC;
