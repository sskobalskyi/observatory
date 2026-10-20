# Generates the Grafana dashboards in ./dashboards. Run from anywhere: pwsh tools/generate-dashboards.ps1
# Generates the Grafana dashboards in ./dashboards (service-overview and k6-load-test).
# Usage: powershell -File tools/generate-dashboards.ps1
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $PSScriptRoot
$prom = @{ type = 'prometheus'; uid = 'prometheus' }
$loki = @{ type = 'loki'; uid = 'loki' }
$script:id = 0
function Target($expr, $legend, $ds = $prom) { @{ datasource = $ds; expr = $expr; legendFormat = $legend; refId = 'A' } }
function Panel($type, $title, $x, $y, $w, $h, $targets, $unit = 'short', $extra = @{}) {
  $script:id++
  $p = @{
    id = $script:id; type = $type; title = $title; datasource = $prom
    gridPos = @{ x = $x; y = $y; w = $w; h = $h }
    targets = @($targets | ForEach-Object -Begin { $i = 0 } -Process { $_.refId = [string][char](65 + $i); $i++; $_ })
    fieldConfig = @{ defaults = @{ unit = $unit }; overrides = @() }
    options = @{}
  }
  foreach ($k in $extra.Keys) { $p[$k] = $extra[$k] }
  $p
}
function Dashboard($uid, $title, $tags, $panels, $templating, $refresh = '5s', $from = 'now-15m') {
  @{ uid = $uid; title = $title; tags = $tags; schemaVersion = 39; version = 1; refresh = $refresh
     time = @{ from = $from; to = 'now' }; panels = $panels; templating = @{ list = $templating }
     annotations = @{ list = @() } }
}
function Save($d, $path) {
  $json = ($d | ConvertTo-Json -Depth 30) + "`n"
  # Grafana's provisioner rejects a UTF-8 BOM, so write without one.
  [IO.File]::WriteAllText((Join-Path $repoRoot $path), $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- Service overview (RED + runtime) ----------
$svc = '{service_name="demo-api"}'
$dur = 'http_server_request_duration_seconds_bucket{service_name="demo-api"}'
$ov = @(
  (Panel 'timeseries' 'Request rate by route (req/s)' 0 0 12 8 @(Target 'sum by (http_route) (rate(http_server_request_duration_seconds_count{service_name="demo-api"}[1m]))' '{{http_route}}') 'reqps'),
  (Panel 'timeseries' 'Error ratio (5xx)' 12 0 12 8 @(Target 'sum(rate(http_server_request_duration_seconds_count{service_name="demo-api",http_response_status_code=~"5.."}[1m])) / sum(rate(http_server_request_duration_seconds_count{service_name="demo-api"}[1m]))' '5xx ratio') 'percentunit'),
  (Panel 'timeseries' 'Latency percentiles (all routes)' 0 8 12 8 @(
      (Target "histogram_quantile(0.50, sum by (le) (rate($dur[1m])))" 'p50'),
      (Target "histogram_quantile(0.95, sum by (le) (rate($dur[1m])))" 'p95'),
      (Target "histogram_quantile(0.99, sum by (le) (rate($dur[1m])))" 'p99')) 's'),
  (Panel 'timeseries' 'p95 latency by route' 12 8 12 8 @(Target "histogram_quantile(0.95, sum by (le, http_route) (rate($dur[1m])))" '{{http_route}}') 's'),
  (Panel 'timeseries' 'Active requests' 0 16 8 7 @(Target 'sum(http_server_active_requests{service_name="demo-api"})' 'active') 'short'),
  (Panel 'timeseries' 'Process CPU (cores)' 8 16 8 7 @(Target 'rate(dotnet_process_cpu_time_seconds_total{service_name="demo-api"}[30s])' '{{dotnet_cpu_state}}') 'short'),
  (Panel 'timeseries' 'Working set' 16 16 8 7 @(Target 'dotnet_process_memory_working_set_bytes{service_name="demo-api"}' 'working set') 'bytes'),
  (Panel 'timeseries' 'GC collections / s by generation' 0 23 8 7 @(Target 'sum by (dotnet_gc_heap_generation) (rate(dotnet_gc_collections_total{service_name="demo-api"}[1m]))' 'gen {{dotnet_gc_heap_generation}}') 'ops'),
  (Panel 'timeseries' 'Thread pool queue length' 8 23 8 7 @(Target 'dotnet_thread_pool_queue_length_total{service_name="demo-api"}' 'queue') 'short'),
  (Panel 'timeseries' 'Simulated failures / s' 16 23 8 7 @(Target 'sum(rate(demo_simulated_failures_total{service_name="demo-api"}[1m]))' 'failures') 'ops'),
  (Panel 'timeseries' 'Database pool: connections in use (max 3)' 0 30 12 7 @(Target 'max(demo_db_pool_in_use{service_name="demo-api"})' 'in use') 'short'),
  (Panel 'timeseries' 'Database pool: timeouts / s (HTTP 503)' 12 30 12 7 @(Target 'sum(rate(demo_db_pool_timeouts_total{service_name="demo-api"}[1m]))' 'timeouts') 'ops'),
  (Panel 'logs' 'Application logs (errors and warnings highlighted)' 0 37 24 9 @(@{ datasource = $loki; expr = '{service_name="demo-api"} | detected_level=~"info|warn|error"'; refId = 'A' }) 'short' @{ datasource = $loki; options = @{ showTime = $true; wrapLogMessage = $true; sortOrder = 'Descending'; enableLogDetails = $true } })
)
Save (Dashboard 'demo-api-overview' 'Service overview: demo-api' @('observatory','red') $ov @()) 'dashboards/service-overview.json'

# ---------- k6 load test ----------
$sel = 'testid=~"$testid"'
$k6 = @(
  (Panel 'stat' 'Current virtual users' 0 0 6 4 @(Target "max(k6_vus{$sel})" 'VUs') 'short'),
  (Panel 'stat' 'Requests / s' 6 0 6 4 @(Target "sum(rate(k6_http_reqs_total{$sel}[30s]))" 'req/s') 'reqps'),
  (Panel 'stat' 'Failed requests' 12 0 6 4 @(Target "max(k6_http_req_failed_rate{$sel})" 'failed') 'percentunit' @{ fieldConfig = @{ defaults = @{ unit = 'percentunit'; thresholds = @{ mode = 'absolute'; steps = @(@{ color = 'green'; value = $null }, @{ color = 'orange'; value = 0.05 }, @{ color = 'red'; value = 0.1 }) } }; overrides = @() } }),
  (Panel 'stat' 'Total requests' 18 0 6 4 @(Target "sum(max by (testid) (k6_http_reqs_total{$sel}))" 'total') 'short'),
  (Panel 'timeseries' 'Virtual users vs request rate' 0 4 12 8 @(
      (Target "max(k6_vus{$sel})" 'VUs'),
      (Target "sum(rate(k6_http_reqs_total{$sel}[30s]))" 'req/s')) 'short'),
  (Panel 'timeseries' 'Client-side response time (k6)' 12 4 12 8 @(
      (Target "avg(k6_http_req_duration_p50{$sel})" 'p50'),
      (Target "avg(k6_http_req_duration_p95{$sel})" 'p95'),
      (Target "avg(k6_http_req_duration_p99{$sel})" 'p99')) 'ms'),
  (Panel 'timeseries' 'Client p95 (k6) vs server p95 (OpenTelemetry)' 0 12 12 8 @(
      (Target "avg(k6_http_req_duration_p95{$sel})" 'client p95 (k6)'),
      (Target 'histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{service_name="demo-api"}[30s]))) * 1000' 'server p95 (app)')) 'ms'),
  (Panel 'timeseries' 'Server CPU during test (cores)' 12 12 12 8 @(Target 'sum(rate(dotnet_process_cpu_time_seconds_total{service_name="demo-api"}[30s]))' 'CPU cores') 'short'),
  (Panel 'timeseries' 'Time spent waiting vs connecting vs receiving (k6, avg)' 0 20 12 8 @(
      (Target "avg(k6_http_req_waiting_avg{$sel})" 'waiting (TTFB)'),
      (Target "avg(k6_http_req_connecting_avg{$sel})" 'connecting'),
      (Target "avg(k6_http_req_receiving_avg{$sel})" 'receiving')) 'ms'),
  (Panel 'timeseries' 'Iteration duration (k6)' 12 20 12 8 @(
      (Target "avg(k6_iteration_duration_p95{$sel})" 'p95'),
      (Target "avg(k6_iteration_duration_avg{$sel})" 'avg')) 'ms')
)
$tpl = @(@{ name = 'testid'; label = 'Test'; type = 'query'; datasource = $prom; query = @{ query = 'label_values(k6_vus, testid)'; refId = 'q' }; refresh = 2; includeAll = $true; allValue = '.*'; current = @{ text = 'All'; value = '$__all' }; multi = $false })
Save (Dashboard 'k6-load-test' 'k6 load test' @('observatory','k6') $k6 $tpl '5s' 'now-30m') 'dashboards/k6-load-test.json'
# ---------- SLO and burn rate ----------
$script:id = 0
$budgetAvail = 'sum(increase(http_server_request_duration_seconds_count{service_name="demo-api",http_response_status_code=~"5.."}[$__range])) / sum(increase(http_server_request_duration_seconds_count{service_name="demo-api"}[$__range]))'
$budgetLatency = '1 - (sum(increase(http_server_request_duration_seconds_bucket{service_name="demo-api",le="0.5"}[$__range])) / sum(increase(http_server_request_duration_seconds_count{service_name="demo-api"}[$__range])))'
$budgetSteps = @{ mode = 'absolute'; steps = @(@{ color = 'red'; value = $null }, @{ color = 'orange'; value = 0.25 }, @{ color = 'green'; value = 0.5 }) }
$burnSteps = @{ mode = 'absolute'; steps = @(@{ color = 'green'; value = $null }, @{ color = 'orange'; value = 6 }, @{ color = 'red'; value = 14.4 }) }
$burnOpts = @{ fieldConfig = @{ defaults = @{ unit = 'short'; custom = @{ thresholdsStyle = @{ mode = 'dashed' } }; thresholds = $burnSteps }; overrides = @() } }
$slo = @(
  (Panel 'stat' 'Availability SLI (selected range)' 0 0 6 5 @(Target "1 - ($budgetAvail)" 'availability') 'percentunit' @{ fieldConfig = @{ defaults = @{ unit = 'percentunit'; decimals = 2; min = 0.9; max = 1 }; overrides = @() } }),
  (Panel 'gauge' 'Availability error budget remaining (99% SLO)' 6 0 6 5 @(Target "1 - (($budgetAvail) / 0.01)" 'budget') 'percentunit' @{ fieldConfig = @{ defaults = @{ unit = 'percentunit'; min = 0; max = 1; thresholds = $budgetSteps }; overrides = @() } }),
  (Panel 'stat' 'Latency SLI: requests under 500 ms (selected range)' 12 0 6 5 @(Target "1 - ($budgetLatency)" 'fast enough') 'percentunit' @{ fieldConfig = @{ defaults = @{ unit = 'percentunit'; decimals = 2; min = 0.5; max = 1 }; overrides = @() } }),
  (Panel 'gauge' 'Latency error budget remaining (95% SLO)' 18 0 6 5 @(Target "1 - (($budgetLatency) / 0.05)" 'budget') 'percentunit' @{ fieldConfig = @{ defaults = @{ unit = 'percentunit'; min = 0; max = 1; thresholds = $budgetSteps }; overrides = @() } }),
  (Panel 'timeseries' 'Availability burn rate (alerts: 14.4 fast, 6 slow)' 0 5 12 9 @(
      (Target 'slo:demo_api_availability_burn_rate:rate1m' '1m'),
      (Target 'slo:demo_api_availability_burn_rate:rate5m' '5m'),
      (Target 'slo:demo_api_availability_burn_rate:rate30m' '30m')) 'short' $burnOpts),
  (Panel 'timeseries' 'Latency burn rate (alerts: 14.4 fast, 6 slow)' 12 5 12 9 @(
      (Target 'slo:demo_api_latency_burn_rate:rate1m' '1m'),
      (Target 'slo:demo_api_latency_burn_rate:rate5m' '5m'),
      (Target 'slo:demo_api_latency_burn_rate:rate30m' '30m')) 'short' $burnOpts),
  (Panel 'timeseries' 'Error ratio vs the 1% budget' 0 14 12 8 @(
      (Target 'slo:demo_api_error_ratio:rate1m' '5xx ratio (1m)'),
      (Target 'vector(0.01)' 'budget (1%)')) 'percentunit'),
  (Panel 'timeseries' 'Requests slower than 500 ms vs the 5% budget' 12 14 12 8 @(
      (Target 'slo:demo_api_slow_ratio:rate1m' 'slow ratio (1m)'),
      (Target 'vector(0.05)' 'budget (5%)')) 'percentunit'),
  (Panel 'table' 'Alerts (pending and firing)' 0 22 24 7 @(@{ datasource = $prom; expr = 'ALERTS{alertstate=~"pending|firing",service_name!=""} or ALERTS{alertstate=~"pending|firing"}'; instant = $true; format = 'table'; refId = 'A' }) 'short' @{ transformations = @(@{ id = 'organize'; options = @{ excludeByName = @{ Time = $true; Value = $true; __name__ = $true } } }) })
)
Save (Dashboard 'demo-api-slo' 'SLO and burn rate: demo-api' @('observatory','slo') $slo @() '5s' 'now-30m') 'dashboards/slo-burn-rate.json'
'done'
