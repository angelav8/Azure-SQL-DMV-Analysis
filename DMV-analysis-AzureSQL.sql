-- Azure SQL Database Performance Monitoring and Optimization Scripts

-- Introduction:
-- These scripts are designed to help you identify and troubleshoot performance bottlenecks
-- in your Azure SQL Databases. They cover active queries, resource consumption, and
-- provide insights for performance optimization.

--Instructions: 
-- 1. Run these scripts one by one in your Azure SQL Database environment.
-- 2. Review the results to identify any performance issues.
-- 3. Use the insights to optimize your database performance, such as creating missing indexes,
--    analyzing long-running queries, and understanding resource consumption patterns.

--Permissions required:
-- Ensure you have the necessary permissions to access DMVs and execute these queries.
-- For database-scoped DMVs, which provide information about a specific database, 
--the VIEW DATABASE STATE permission is required. 
--This permission allows a user to see information about all objects within that particular database.

-- 1. DMVs for Active Queries (What's happening right now)
-- This query shows currently executing requests, including their status, command,
-- and the SQL text being executed. It's useful for identifying long-running or blocked queries.

SELECT
    s.session_id,
    r.command,
    r.status,
    r.wait_type,
    r.wait_time,
    r.last_wait_type,
    r.cpu_time,
    r.total_elapsed_time,
    r.reads,
    r.writes,
    r.logical_reads,
    r.blocking_session_id,
    DB_NAME(r.database_id) AS database_name,
    s.host_name,
    s.program_name,
    s.login_name,
    t.text AS sql_command_text,
    qp.query_plan
FROM
    sys.dm_exec_requests r
JOIN
    sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY
    sys.dm_exec_sql_text(r.sql_handle) t
OUTER APPLY
    sys.dm_exec_query_plan(r.plan_handle) qp
WHERE
    s.is_user_process = 1 -- Exclude system processes
ORDER BY
    r.total_elapsed_time DESC;

-- To find blocked queries:
SELECT
    t1.resource_type,
    t1.resource_database_id,
    t1.resource_associated_entity_id,
    t1.request_mode,
    t1.request_status,
    t1.request_owner_type,
    t1.request_session_id,
    t2.blocking_session_id,
    t2.last_wait_type,
    t2.wait_time,
    t2.wait_type,
    t2.command,
    t3.text AS blocked_sql_text,
    t4.text AS blocking_sql_text
FROM
    sys.dm_tran_locks t1
INNER JOIN
    sys.dm_exec_requests t2 ON t1.request_session_id = t2.session_id
OUTER APPLY
    sys.dm_exec_sql_text(t2.sql_handle) t3
OUTER APPLY
    sys.dm_exec_sql_text( (SELECT sql_handle FROM sys.dm_exec_requests WHERE session_id = t2.blocking_session_id) ) t4
WHERE
    t1.request_status = 'WAIT' AND t2.blocking_session_id IS NOT NULL;


-- 2. sp_who2 and Alternatives for Azure SQL Database
-- While sp_who2 is commonly used in on-premises SQL Server, it's not the recommended
-- or most efficient way to monitor Azure SQL Database.
-- Instead, use DMVs like sys.dm_exec_sessions and sys.dm_exec_requests for more detailed information.

-- Script to get session information (similar to sp_who2 but more powerful):
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    s.cpu_time,
    s.memory_usage,
    s.last_request_start_time,
    s.last_request_end_time,
    s.reads,
    s.writes,
    s.logical_reads,
    r.command,
    r.status AS request_status,
    r.wait_type,
    r.wait_time,
    t.text AS current_sql_text
FROM
    sys.dm_exec_sessions s
LEFT JOIN
    sys.dm_exec_requests r ON s.session_id = r.session_id
OUTER APPLY
    sys.dm_exec_sql_text(r.sql_handle) t
WHERE
    s.is_user_process = 1
ORDER BY
    s.session_id;

-- 3. DMVs for I/O and CPU Consumption

-- Database Resource Consumption (CPU, Data I/O, Log I/O) - Historical Data
-- This DMV provides historical resource usage data for your database, aggregated every 5 minutes.
-- It's excellent for spotting trends and identifying periods of high resource consumption.

SELECT
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_log_write_percent,
    avg_memory_usage_percent,
    xtp_storage_percent,
    max_worker_percent,
    max_session_percent,
    dtu_limit,
    avg_dtu_percent,
    max_dtu_percent
FROM
    sys.dm_db_resource_stats
ORDER BY
    end_time DESC;

-- File I/O Statistics (for understanding disk activity)
-- This DMV provides I/O statistics for data and log files.
-- Useful for identifying I/O intensive operations or slow storage.

SELECT
    DB_NAME(database_id) AS database_name,
    file_id,
    io_stall_queued_ms,
    num_of_reads,
    num_of_writes,
    io_stall_read_ms,
    io_stall_write_ms,
    io_stall_read_ms + io_stall_write_ms AS total_io_stall_ms,
    size_on_disk_bytes
FROM
    sys.dm_io_virtual_file_stats(DB_ID(), NULL)
ORDER BY
    total_io_stall_ms DESC;

-- Wait Statistics (Understanding what the database is waiting on)
-- This DMV shows aggregated information about all the waits encountered by threads that executed.
-- High wait times for specific types can indicate bottlenecks (e.g., PAGEIOLATCH_SH for I/O, CXPACKET for parallelism).

SELECT
    wait_type,
    SUM(wait_time_ms) AS total_wait_time_ms,
    SUM(waiting_tasks_count) AS total_waiting_tasks,
    SUM(signal_wait_time_ms) AS total_signal_wait_time_ms,
    CAST(SUM(wait_time_ms) * 100.0 / SUM(SUM(wait_time_ms)) OVER() AS DECIMAL(5, 2)) AS percentage_of_total_wait_time
FROM
    sys.dm_os_wait_stats
WHERE
    wait_type NOT IN (
        'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP', 'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER',
        'CHECKPOINT_QUEUE', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE',
        'DBCC_SPECIFY_SYSTEM_MESSAGES', 'DTC_STATE', 'DTC_TMDOWN_REQUEST', 'DTC_TMREQUEST',
        'EXTENDED_PROCEDURE_CALL', 'FT_IFTS_SCHEDULER_IDLE_WAIT', 'KTM_ENLISTMENT',
        'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE', 'ONDEMAND_TASK_QUEUE',
        'PREEMPTIVE_OS_FOR_REPLICATION_AGENTS', 'PREEMPTIVE_OS_GETPROCADDRESS',
        'PREEMPTIVE_OS_WAITFORSINGLEOBJECT', 'PREEMPTIVE_OS_WRITEFILE',
        'PWAIT_EXTENSIBILITY_CLEANUP', 'PWAIT_EXTENSIBILITY_MANAGER',
        'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'REQUEST_FOR_DEADLOCK_SEARCH', 'RESOURCE_QUEUE',
        'SLEEP_TASK', 'SP_SERVER_DIAGNOSTICS_SLEEP', 'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_WAIT_ENTRIES',
        'WAITFOR', 'WAITFOR_TASKSHUTDOWN', 'WAIT_FOR_RESULTS', 'XE_DISPATCHER_JOIN',
        'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT', 'XTP_PREEMPTIVE_TASK'
    )
GROUP BY
    wait_type
ORDER BY
    total_wait_time_ms DESC;

-- 4. Queries for Performance Optimization

-- Missing Indexes (Crucial for performance)
-- This DMV helps identify indexes that, if created, could significantly improve query performance.
-- Review these suggestions carefully and test them in a non-production environment first.

SELECT
    dm_mid.database_id,
    DB_NAME(dm_mid.database_id) AS database_name,
    dm_migs.avg_total_user_cost * (dm_migs.avg_user_impact / 100.0) AS estimated_impact,
    dm_migs.last_user_seek,
    dm_mid.object_id,
    OBJECT_NAME(dm_mid.object_id, dm_mid.database_id) AS table_name,
    'CREATE INDEX IX_' + OBJECT_NAME(dm_mid.object_id, dm_mid.database_id) + '_'
    + REPLACE(REPLACE(REPLACE(ISNULL(dm_mid.equality_columns, ''), ', ', '_'), '[', ''), ']', '')
    + CASE WHEN dm_mid.equality_columns IS NOT NULL AND dm_mid.inequality_columns IS NOT NULL THEN '_' ELSE '' END
    + REPLACE(REPLACE(REPLACE(ISNULL(dm_mid.inequality_columns, ''), ', ', '_'), '[', ''), ']', '')
    + CASE WHEN dm_mid.included_columns IS NOT NULL THEN '_Included' ELSE '' END
    + ' ON ' + SCHEMA_NAME(tbl.schema_id) + '.' + OBJECT_NAME(dm_mid.object_id, dm_mid.database_id)
    + ' (' + ISNULL(dm_mid.equality_columns, '')
    + CASE WHEN dm_mid.equality_columns IS NOT NULL AND dm_mid.inequality_columns IS NOT NULL THEN ', ' ELSE '' END
    + ISNULL(dm_mid.inequality_columns, '')
    + ')'
    + ISNULL(' INCLUDE (' + dm_mid.included_columns + ')', '') AS create_index_statement
FROM
    sys.dm_db_missing_index_details dm_mid
JOIN
    sys.dm_db_missing_index_groups dm_migs ON dm_migs.index_handle = dm_mid.index_handle
JOIN
    sys.dm_db_missing_index_group_stats dm_mig ON dm_migs.index_group_handle = dm_mig.group_handle
JOIN
    sys.tables tbl ON dm_mid.object_id = tbl.object_id
ORDER BY
    estimated_impact DESC;

-- Top N Queries by CPU Usage (from Query Store)
-- Azure SQL Database has Query Store enabled by default. This is an invaluable tool
-- for historical performance analysis. This query shows the top queries consuming CPU.

SELECT TOP 20
    qtext.query_sql_text,
    qs.query_id,
    qtt.query_hash,
    SUM(rs.count_executions) AS total_executions,
    SUM(rs.avg_cpu_time * rs.count_executions) AS total_cpu_time_ms,
    SUM(rs.avg_duration * rs.count_executions) AS total_duration_ms,
    SUM(rs.avg_logical_io_reads * rs.count_executions) AS total_logical_reads,
    MAX(rs.max_cpu_time) AS max_cpu_time_ms,
    MAX(rs.max_duration) AS max_duration_ms,
    MAX(rs.max_logical_io_reads) AS max_logical_reads
FROM
    sys.query_store_query_text qtext
JOIN
    sys.query_store_query qs ON qtext.query_text_id = qs.query_text_id
JOIN
    sys.query_store_plan qp ON qs.query_id = qp.query_id
JOIN
    sys.query_store_runtime_stats rs ON qp.plan_id = rs.plan_id
JOIN
    sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
JOIN
    sys.query_store_query_text qtt ON qs.query_text_id = qtt.query_text_id
WHERE
    rsi.start_time >= DATEADD(hour, -24, GETUTCDATE()) -- Last 24 hours
GROUP BY
    qtext.query_sql_text, qs.query_id, qtt.query_hash
ORDER BY
    total_cpu_time_ms DESC;

-- Top N Long-Running Queries (from Query Store)
-- This query helps identify queries that consistently take a long time to execute.

SELECT TOP 20
    qtext.query_sql_text,
    qs.query_id,
    qtt.query_hash,
    SUM(rs.count_executions) AS total_executions,
    SUM(rs.avg_duration * rs.count_executions) AS total_duration_ms,
    SUM(rs.avg_cpu_time * rs.count_executions) AS total_cpu_time_ms,
    SUM(rs.avg_logical_io_reads * rs.count_executions) AS total_logical_reads,
    MAX(rs.max_duration) AS max_duration_ms,
    MAX(rs.max_cpu_time) AS max_cpu_time_ms,
    MAX(rs.max_logical_io_reads) AS max_logical_reads
FROM
    sys.query_store_query_text qtext
JOIN
    sys.query_store_query qs ON qtext.query_text_id = qs.query_text_id
JOIN
    sys.query_store_plan qp ON qs.query_id = qp.query_id
JOIN
    sys.query_store_runtime_stats rs ON qp.plan_id = rs.plan_id
JOIN
    sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
JOIN
    sys.query_store_query_text qtt ON qs.query_text_id = qtt.query_text_id
WHERE
    rsi.start_time >= DATEADD(hour, -24, GETUTCDATE()) -- Last 24 hours
GROUP BY
    qtext.query_sql_text, qs.query_id, qtt.query_hash
ORDER BY
    total_duration_ms DESC;

-- Index Usage Statistics
-- Provides information on how indexes are being used (seeks, scans, lookups, updates).
-- Useful for identifying unused or underutilized indexes that could be dropped.

SELECT
    OBJECT_NAME(s.object_id) AS table_name,
    i.name AS index_name,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates,
    s.last_user_seek,
    s.last_user_scan,
    s.last_user_lookup,
    s.last_user_update
FROM
    sys.dm_db_index_usage_stats s
JOIN
    sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE
    OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
    AND s.database_id = DB_ID()
ORDER BY
    (s.user_seeks + s.user_scans + s.user_lookups) DESC;

-- Index Fragmentation
-- This query helps identify indexes that are fragmented and may need to be rebuilt or reorganized.
SELECT
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    ps.avg_fragmentation_in_percent,
    ps.page_count,
    ps.avg_page_space_used_in_percent,
    ps.record_count
FROM
    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
JOIN 
    sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE
    OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND ps.database_id = DB_ID()
    AND ps.avg_fragmentation_in_percent > 10 -- Adjust threshold as needed
ORDER BY
    ps.avg_fragmentation_in_percent DESC;       
-- Note: For indexes with high fragmentation, consider rebuilding or reorganizing them.