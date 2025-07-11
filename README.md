### Why is my database slow? 

A question every DBA is asked, this repo will hold scripts for basic queries designed to find bottlenecks in Azure SQL and Managed instance databases. 

You should be monitoring loads regularly to notice when wait times change or go up. 

Typically we look at the following 
- CPU load on the server 
- Active queries by user 
- Blocked queries 

Analyzing the performance and health of an Azure SQL database is crucial for maintaining optimal operation. Dynamic Management Views (DMVs) are indispensable tools for this, providing a window into the inner workings of the database engine. Below is a breakdown of the most useful DMV tables and their key columns, categorized by their primary function.

### Execution-Related DMVs

These DMVs are fundamental for understanding query performance and identifying bottlenecks in your T-SQL code.

\<hr\>

#### **`sys.dm_exec_query_stats`**

This DMV provides aggregate performance statistics for cached query plans. It's invaluable for identifying high-resource queries over time.

| Column | Description |
| --- | --- |
| **`total_worker_time`** | Total CPU time, in microseconds, consumed by executions of this plan. A high value indicates a CPU-intensive query. |
| **`total_elapsed_time`** | Total time, in microseconds, that the query has been running. This helps identify long-running queries. |
| **`total_logical_reads`** | Total number of logical reads performed by the query. High values can indicate inefficient indexing. |
| **`total_logical_writes`** | Total number of logical writes performed by the query. Useful for understanding the write activity of a query. |
| **`execution_count`** | The number of times the plan has been executed since it was last compiled. Helps in identifying frequently executed queries. |
| **`sql_handle`** | A token that uniquely identifies the batch or stored procedure of the query. Used to retrieve the query text from `sys.dm_exec_sql_text`. |
| **`plan_handle`** | A token that uniquely identifies the execution plan. Used to retrieve the plan from `sys.dm_exec_query_plan`. |

-----

#### **`sys.dm_exec_requests`**

This DMV shows information about each request currently executing in the Azure SQL database. It provides a real-time snapshot of ongoing activity.

| Column | Description |
| --- | --- |
| **`session_id`** | The ID of the session in which the request is running. |
| **`status`** | The status of the request (e.g., `running`, `runnable`, `suspended`, `sleeping`). `suspended` indicates the query is waiting for a resource. |
| **`command`** | The type of command being executed (e.g., `SELECT`, `INSERT`, `UPDATE`, `DELETE`). |
| **`blocking_session_id`** | If the request is blocked, this shows the session ID of the blocking session. |
| **`wait_type`** | The type of wait the request is currently experiencing. Essential for diagnosing performance issues. |
| **`wait_time`** | The duration, in milliseconds, of the current wait. |
| **`total_elapsed_time`** | The total time elapsed, in milliseconds, since the request began. |
| **`cpu_time`** | The CPU time, in milliseconds, used by the request. |

\<hr\>

### Index-Related DMVs

Proper indexing is critical for query performance. These DMVs help you understand how your indexes are being used and identify opportunities for improvement.

#### **`sys.dm_db_index_usage_stats`**

This DMV tracks the usage of indexes, including the number of seeks, scans, and updates.

| Column | Description |
| --- | --- |
| **`user_seeks`** | The number of times the index was used for a seek operation by a user query. High numbers are generally good. |
| **`user_scans`** | The number of times the index was scanned by a user query. High numbers might indicate a need for a more selective index. |
| **`user_lookups`** | The number of times a bookmark lookup was performed. This can indicate that the index doesn't cover all the columns needed by the query. |
| **`user_updates`** | The number of times the index was maintained due to data modifications (inserts, updates, deletes). |
| **`last_user_seek`**, **`last_user_scan`** | The last time a seek or scan was performed. Helps in identifying unused indexes. |

-----

#### **`sys.dm_db_missing_index_details`**, **`sys.dm_db_missing_index_group_stats`**, and **`sys.dm_db_missing_index_groups`**

These DMVs work together to suggest new indexes that could improve query performance.

| DMV | Key Columns |
| --- | --- |
| **`sys.dm_db_missing_index_details`** | `equality_columns`, `inequality_columns`, `included_columns`: These columns suggest the key and included columns for the missing index. |
| **`sys.dm_db_missing_index_group_stats`** | `avg_user_impact`: An estimate of the percentage improvement the missing index could provide. |

\<hr\>

### Resource and Wait-Related DMVs

Understanding resource consumption and wait statistics is key to identifying and resolving performance bottlenecks.

#### **`sys.dm_os_wait_stats`**

This DMV provides cumulative wait statistics since the last time the SQL Server instance was restarted. It's crucial for diagnosing resource contention.

| Column | Description |
| --- | --- |
| **`wait_type`** | The name of the wait type. Common waits include `PAGEIOLATCH_*` (I/O waits), `WRITELOG` (log write waits), and `CXPACKET` (parallelism waits). |
| **`wait_time_ms`** | The total time, in milliseconds, that queries have waited for this type. |
| **`waiting_tasks_count`** | The number of times queries have waited for this type. |
| **`signal_wait_time_ms`** | The time, in milliseconds, that threads spent waiting for the CPU after being signaled that their resource was available. A high value can indicate CPU pressure. |

-----

#### **`sys.dm_db_resource_stats`**

This DMV provides a near real-time view of resource consumption for the current Azure SQL database. It captures data every 15 seconds and retains it for approximately one hour.

| Column | Description |
| --- | --- |
| **`end_time`** | The UTC time indicating the end of the 15-second reporting interval. |
| **`avg_cpu_percent`** | Average compute utilization as a percentage of the limit for the service tier. |
| **`avg_data_io_percent`** | Average data I/O utilization as a percentage of the limit. |
| **`avg_log_write_percent`** | Average log write utilization as a percentage of the limit. |
| **`dtu_limit`** or **`cpu_limit`** | The maximum DTU or vCore limit for the database at the time. |
