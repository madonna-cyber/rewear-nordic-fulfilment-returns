# Rewear Nordic: rebuild kit

Everything you need to rebuild the Power BI file: the Power Query cleaning (all 7 tables), the relationships, and the DAX. Work top to bottom. **Save as `Rewear_Nordic.pbix` after step 1 and again after every few queries.**

---

## Part 1: Set up Power Query

1. Open Power BI Desktop and **File → Save as → `Rewear_Nordic.pbix`** (pick a folder you will remember, like Documents).
2. **Home → Transform data** opens the Power Query Editor.
3. For each block below: **Home → New Source → Blank Query**, then **Home → Advanced Editor**, select everything in the box, delete it, paste the block, click **Done**. Then rename the query (Query Settings pane on the right, "Name" box) to the exact name in the block's heading.
4. Create them in this order: `Raw`, `fnNum`, `fnDT`, then the 7 tables.

If you see a yellow bar asking about **privacy levels or "Formula.Firewall"**, choose **Ignore privacy levels** or go to File → Options → Security/Privacy and tick "Always ignore Privacy Level settings".

### Query name: `Raw`

Replace the file path with yours. Easy way: in File Explorer, click your Excel file, press **Ctrl+Shift+C** (copy as path), and paste it between the quote marks, removing the quotes Windows adds. Close the Excel file first.

```
let
    Source = Excel.Workbook(File.Contents("C:\Users\YOURNAME\Documents\Raw_Dataset working.xlsx"), null, true)
in
    Source
```

After creating it, right-click `Raw` in the Queries pane and **untick Enable load**.

### Query name: `fnNum`

Converts text like `340,00 kr` or `32,08 SEK` to a number, and leaves real numbers alone.

```
(x as any) as nullable number =>
if x = null then null
else if x is number then x
else try Number.FromText(Text.Trim(Text.Replace(Text.Replace(Text.From(x), "kr", ""), "SEK", "")), "sv-SE") otherwise null
```

### Query name: `fnDT`

Converts day-first text like `23/01/2025 19:55` to a date and time, and leaves real dates alone.

```
(x as any) as nullable datetime =>
if x = null then null
else if x is datetime then x
else if x is date then DateTime.From(x)
else try DateTime.FromText(Text.Trim(Text.From(x)), "en-GB") otherwise null
```

---

## Part 2: The seven tables

### Query name: `T_Warehouses`

```
let
    Source = Raw{[Item="T_Warehouses",Kind="Table"]}[Data],
    Typed = Table.TransformColumnTypes(Source, {{"Warehouse_ID", type text}, {"Warehouse_Name", type text}, {"City", type text}, {"Daily_Order_Capacity", Int64.Type}})
in
    Typed
```

### Query name: `T_Customers`

```
let
    Source = Raw{[Item="T_Customers",Kind="Table"]}[Data],
    TrimRegion = Table.TransformColumns(Source, {{"Region", Text.Trim, type text}}),
    FixChannel = Table.TransformColumns(TrimRegion, {{"Acquisition_Channel", each if _ = null or Text.Trim(_) = "" then "Unknown" else Text.Upper(Text.Start(Text.Trim(_), 1)) & Text.Lower(Text.Middle(Text.Trim(_), 1)), type text}}),
    Typed = Table.TransformColumnTypes(FixChannel, {{"Customer_ID", type text}, {"Registered_Date", type date}, {"Membership", type text}})
in
    Typed
```

### Query name: `T_Products`

```
let
    Source = Raw{[Item="T_Products",Kind="Table"]}[Data],
    Category1 = Table.TransformColumns(Source, {{"Category", each Text.Proper(Text.Trim(_)), type text}}),
    Category2 = Table.ReplaceValue(Category1, "Shoes", "Footwear", Replacer.ReplaceValue, {"Category"}),
    Condition1 = Table.TransformColumns(Category2, {{"Condition", Text.Trim, type text}}),
    Condition2 = Table.ReplaceValue(Condition1, "Verry good", "Very good", Replacer.ReplaceValue, {"Condition"}),
    Price = Table.TransformColumns(Condition2, {{"List_Price_SEK", fnNum, type number}}),
    Typed = Table.TransformColumnTypes(Price, {{"Product_ID", type text}, {"Warehouse_ID", type text}, {"Item_Type", type text}, {"Brand_Tier", type text}, {"Size", type text}, {"Listed_Date", type date}})
in
    Typed
```

### Query name: `T_Orders`

```
let
    Source = Raw{[Item="T_Orders",Kind="Table"]}[Data],
    Timestamp = Table.TransformColumns(Source, {{"Order_Timestamp", fnDT, type datetime}}),
    Channel = Table.TransformColumns(Timestamp, {{"Sales_Channel", Text.Trim, type text}}),
    Payment = Table.ReplaceValue(Channel, "Credit card", "Card", Replacer.ReplaceValue, {"Payment_Method"}),
    Status1 = Table.TransformColumns(Payment, {{"Order_Status", Text.Trim, type text}}),
    Status2 = Table.ReplaceValue(Status1, "Complete", "Completed", Replacer.ReplaceValue, {"Order_Status"}),
    Status3 = Table.ReplaceValue(Status2, "completed", "Completed", Replacer.ReplaceValue, {"Order_Status"}),
    Customer = Table.ReplaceValue(Status3, null, "Unknown", Replacer.ReplaceValue, {"Customer_ID"}),
    Service = Table.TransformColumns(Customer, {{"Delivery_Service", Text.Trim, type text}}),
    Typed = Table.TransformColumnTypes(Service, {{"Order_ID", type text}, {"Customer_ID", type text}, {"Payment_Method", type text}, {"Delivery_Fee_SEK", type number}, {"Delivery_Fee_Refund_SEK", type number}}),
    NoDuplicates = Table.Distinct(Typed)
in
    NoDuplicates
```

### Query name: `T_Order_Items`

```
let
    Source = Raw{[Item="T_Order_Items",Kind="Table"]}[Data],
    Price = Table.TransformColumns(Source, {{"Sale_Price_SEK", fnNum, type number}}),
    Flag = Table.AddColumn(Price, "Entitlement_Flag", each if Number.Round([Seller_Entitlement_SEK] / [Sale_Price_SEK], 2) = 0.6 then "OK" else "Check", type text),
    Typed = Table.TransformColumnTypes(Flag, {{"Order_Item_ID", type text}, {"Order_ID", type text}, {"Product_ID", type text}, {"Quantity", Int64.Type}, {"Seller_Entitlement_SEK", type number}})
in
    Typed
```

### Query name: `T_Fulfilment`

```
let
    Source = Raw{[Item="T_Fulfilment",Kind="Table"]}[Data],
    DateCols = {"Promised_Dispatch_At", "Pick_Started_At", "Pack_Completed_At", "Dispatched_At", "Promised_Delivery_At", "Delivered_At"},
    Dates = Table.TransformColumns(Source, List.Transform(DateCols, each {_, fnDT, type datetime})),
    Costs = Table.TransformColumns(Dates, {{"Handling_Cost_SEK", fnNum, type number}, {"Packaging_Cost_SEK", fnNum, type number}, {"Carrier_Cost_SEK", fnNum, type number}}),
    HandlingFlag = Table.AddColumn(Costs, "Handling_Flag", each if [Handling_Cost_SEK] < 0 then "Negative" else "OK", type text),
    HandlingAbs = Table.TransformColumns(HandlingFlag, {{"Handling_Cost_SEK", Number.Abs, type number}}),
    Chronology = Table.AddColumn(HandlingAbs, "Chronology_Flag", each if [Delivered_At] <> null and [Dispatched_At] <> null and [Delivered_At] < [Dispatched_At] then "Check" else "OK", type text),
    CarrierTrim = Table.TransformColumns(Chronology, {{"Carrier", Text.Trim, type text}}),
    Carrier1 = Table.ReplaceValue(CarrierTrim, "sveaparcel", "SveaParcel", Replacer.ReplaceValue, {"Carrier"}),
    Carrier2 = Table.ReplaceValue(Carrier1, "nordship", "NordShip", Replacer.ReplaceValue, {"Carrier"}),
    Carrier3 = Table.ReplaceValue(Carrier2, "citybox", "CityBox", Replacer.ReplaceValue, {"Carrier"}),
    Carrier4 = Table.ReplaceValue(Carrier3, null, "Not Shipped", Replacer.ReplaceValue, {"Carrier"}),
    WH1 = Table.AddColumn(Carrier4, "Warehouse_Fixed", each if Text.Trim([Warehouse_ID]) = "WH-OLD" then (if List.Contains({"RN-000090", "RN-003978"}, [Order_ID]) then "WH-STO" else "WH-GOT") else Text.Trim([Warehouse_ID]), type text),
    WH2 = Table.RemoveColumns(WH1, {"Warehouse_ID"}),
    WH3 = Table.RenameColumns(WH2, {{"Warehouse_Fixed", "Warehouse_ID"}}),
    Typed = Table.TransformColumnTypes(WH3, {{"Fulfilment_ID", type text}, {"Order_ID", type text}, {"Fulfilment_Status", type text}})
in
    Typed
```

### Query name: `T_Returns`

```
let
    Source = Raw{[Item="T_Returns",Kind="Table"]}[Data],
    Dates = Table.TransformColumns(Source, {{"Requested_At", fnDT, type datetime}, {"Received_At", fnDT, type datetime}, {"Processed_At", fnDT, type datetime}}),
    Reason = Table.TransformColumns(Dates, {{"Return_Reason", each if _ = null or Text.Trim(_) = "" then "Not recorded" else Text.Upper(Text.Start(Text.Trim(_), 1)) & Text.Lower(Text.Middle(Text.Trim(_), 1)), type text}}),
    Flag = Table.AddColumn(Reason, "Chronology_Flag", each if [Processed_At] <> null and [Received_At] <> null and [Processed_At] < [Received_At] then "Check" else "OK", type text),
    Typed = Table.TransformColumnTypes(Flag, {{"Return_ID", type text}, {"Order_Item_ID", type text}, {"Return_Status", type text}, {"Refund_Amount_SEK", type number}, {"Return_Handling_Cost_SEK", type number}, {"Return_Carrier_Cost_SEK", type number}})
in
    Typed
```

---

## Part 3: Check before you load

Turn on **View → Column quality / Column distribution / Column profile**, and set profiling to **entire data set** (bottom bar). Then confirm:

| Table | Rows | Other checks |
|---|---|---|
| T_Orders | 4,975 | Order_Status: 3 values. Sales_Channel: 2. Payment_Method: 3. Order_Timestamp error 0% |
| T_Fulfilment | 4,975 | Carrier: 4 values (incl. Not Shipped). Warehouse_ID: 2. Carrier_Cost Max 76.65. Handling_Cost Min 0, Max 44.41 |
| T_Order_Items | 9,115 | Sale_Price Max 6,447.11. Entitlement_Flag "Check" = 4 rows |
| T_Products | 9,115 | Category: 7 values. Condition: 3 values. List_Price Min about 25, Max about 6,447 |
| T_Returns | 1,084 | Return_Reason: 7 values. Chronology_Flag "Check" = 4 rows |
| T_Customers | 2,200 | Region: 9 values. Acquisition_Channel: 6 values |
| T_Warehouses | 2 | Daily_Order_Capacity is a whole number |

Then **Home → Close & Apply**, and **save**.

---

## Part 4: Relationships (Model view)

Delete any extra lines Power BI guesses, and make sure these seven exist (all One to many, single direction, except Orders to Fulfilment which is One to one):

| One side | Many side |
|---|---|
| T_Customers[Customer_ID] | T_Orders[Customer_ID] |
| T_Orders[Order_ID] | T_Fulfilment[Order_ID] (one-to-one) |
| T_Orders[Order_ID] | T_Order_Items[Order_ID] |
| T_Products[Product_ID] | T_Order_Items[Product_ID] |
| T_Order_Items[Order_Item_ID] | T_Returns[Order_Item_ID] |
| T_Warehouses[Warehouse_ID] | T_Fulfilment[Warehouse_ID] |
| Dim_Date[Date] | T_Orders[Order_Date] (after Part 5) |

---

## Part 5: DAX

Type these in fresh. If pasted quotes cause errors, retype the quote marks.

**Order date column** (right-click T_Orders, or Table tools → New column):

```
Order_Date = DATE(YEAR(T_Orders[Order_Timestamp]), MONTH(T_Orders[Order_Timestamp]), DAY(T_Orders[Order_Timestamp]))
```

**Date table** (Modeling → New table):

```
Dim_Date =
ADDCOLUMNS(
    CALENDAR(DATE(2025,1,1), DATE(2025,12,31)),
    "Year", YEAR([Date]),
    "Month No", MONTH([Date]),
    "Month", FORMAT([Date], "mmm"),
    "Year-Month", FORMAT([Date], "yyyy-mm")
)
```

Then: sort `Month` by `Month No`, right-click `Dim_Date` and **Mark as date table** using `Date`, and link `Dim_Date[Date]` to `T_Orders[Order_Date]`.

**Measures** (right-click T_Orders, New measure, one at a time):

```
Orders = CALCULATE(DISTINCTCOUNT(T_Orders[Order_ID]), T_Orders[Order_Status] <> "Cancelled")
```
```
Dispatched Orders = COUNT(T_Fulfilment[Dispatched_At])
```
```
Late Dispatch Orders =
CALCULATE(
    COUNTROWS(T_Fulfilment),
    FILTER(
        T_Fulfilment,
        NOT ISBLANK(T_Fulfilment[Dispatched_At]) &&
        T_Fulfilment[Dispatched_At] > T_Fulfilment[Promised_Dispatch_At]
    )
)
```
```
Late Dispatch % = DIVIDE([Late Dispatch Orders], [Dispatched Orders])
```
```
Delivered Orders = COUNT(T_Fulfilment[Delivered_At])
```
```
Late Delivery Orders =
CALCULATE(
    COUNTROWS(T_Fulfilment),
    FILTER(
        T_Fulfilment,
        NOT ISBLANK(T_Fulfilment[Delivered_At]) &&
        T_Fulfilment[Delivered_At] > T_Fulfilment[Promised_Delivery_At]
    )
)
```
```
Late Delivery % = DIVIDE([Late Delivery Orders], [Delivered Orders])
```
```
Return Rate % =
DIVIDE(
    COUNTROWS(T_Returns),
    CALCULATE(COUNTROWS(T_Order_Items), T_Orders[Order_Status] = "Completed")
)
```
```
Avg Fulfilment Cost =
CALCULATE(
    AVERAGEX(
        T_Fulfilment,
        T_Fulfilment[Handling_Cost_SEK] + T_Fulfilment[Packaging_Cost_SEK] + T_Fulfilment[Carrier_Cost_SEK]
    ),
    FILTER(T_Fulfilment, NOT ISBLANK(T_Fulfilment[Dispatched_At]))
)
```

Formats: counts as Whole number, percentages as Percentage with 1 decimal, cost as Decimal number with 2 places.

---

## Part 6: Final checks (no filters)

| Measure | Expected |
|---|---|
| Orders | 4,818 |
| Late Dispatch Orders | 680 |
| Late Dispatch % | 14.1% |
| Delivered Orders | 4,777 |
| Late Delivery Orders | 1,027 |
| Late Delivery % | 21.5% |
| Return Rate % | about 12.4% |
| Avg Fulfilment Cost | about 75.07 |

By warehouse, Late Dispatch % should be about 17.1% for Mölndal and 12.2% for Arlanda.

**Save the file now.**
