# Trace Summary

- Generated: 2026-04-05T01:36:54Z
- Trace: `/Users/qinkan/Library/Application Support/Luma/Diagnostics/runtime-latest.jsonl`
- Session: `D7D98F70-C93B-4246-81E8-9A29E00928AC`
- Records: 189
- Parse failures: 0
- Time range: 2026-04-05T01:36:10Z -> 2026-04-05T01:36:41Z

## Levels

- `metric` · 112
- `info` · 77

## Categories

- `state` · 99
- `grouping` · 68
- `import` · 14
- `app` · 7
- `project` · 1

## Top Events

- 99x · `metric` · `state` · `derived_state_rebuilt`
- 59x · `info` · `grouping` · `burst_candidate`
- 5x · `info` · `grouping` · `scene_cut_candidate`
- 5x · `info` · `import` · `import_phase_changed`
- 4x · `info` · `app` · `app_activation_attempted`
- 1x · `metric` · `app` · `bootstrap_completed`
- 1x · `info` · `app` · `bootstrap_started`
- 1x · `info` · `app` · `session_started`
- 1x · `metric` · `grouping` · `grouping_completed`
- 1x · `metric` · `grouping` · `grouping_location_naming_completed`

## Slow Metrics

- `import/import_completed` · count=1 · avg=11914.37ms · p50=11914.37ms · p95=11914.37ms · max=11914.37ms
- `import/import_run_completed` · count=1 · avg=9242.26ms · p50=9242.26ms · p95=9242.26ms · max=9242.26ms
- `import/import_grouping_completed` · count=1 · avg=6956.34ms · p50=6956.34ms · p95=6956.34ms · max=6956.34ms
- `grouping/grouping_completed` · count=1 · avg=6956.00ms · p50=6956.00ms · p95=6956.00ms · max=6956.00ms
- `grouping/grouping_location_naming_completed` · count=1 · avg=6299.00ms · p50=6299.00ms · p95=6299.00ms · max=6299.00ms
- `import/initial_manifest_built` · count=1 · avg=1913.32ms · p50=1913.32ms · p95=1913.32ms · max=1913.32ms
- `grouping/grouping_subgrouping_completed` · count=1 · avg=1528.97ms · p50=1528.97ms · p95=1528.97ms · max=1528.97ms
- `grouping/grouping_scene_split_completed` · count=1 · avg=656.00ms · p50=656.00ms · p95=656.00ms · max=656.00ms
- `import/preview_copy_completed` · count=1 · avg=205.22ms · p50=205.22ms · p95=205.22ms · max=205.22ms
- `import/import_source_enumerated` · count=1 · avg=135.08ms · p50=135.08ms · p95=135.08ms · max=135.08ms

## Hotspot Budgets

- `import/import_grouping_completed` · budget=1000ms · count=1 · breaches=1 · p95=6956.34ms · max=6956.34ms · breach
- `import/initial_manifest_built` · budget=1000ms · count=1 · breaches=1 · p95=1913.32ms · max=1913.32ms · breach
- `app/bootstrap_completed` · budget=80ms · count=1 · breaches=0 · p95=26.32ms · max=26.32ms · ok
- `state/derived_state_rebuilt` · budget=8ms · count=99 · breaches=0 · p95=0.33ms · max=0.37ms · ok

## Slow Chains

- #7 · `app/bootstrap_completed` · total=26.32ms · budget=150ms · max-stage=26.32ms · stages=1 · project_name=luma_test_1 selected_group_id=all selected_asset_id=8B29F849-9655-4849-90D1-C84D1AFD0545
  - app/bootstrap_completed 26.32ms

## Slow Samples

- #96 · `import/import_completed` · 11914.37ms · project_name=luma_test_1 selected_group_id=all selected_asset_id=D4FCF0FE-D8B2-4108-A7E1-DA46AF618CB9
- #93 · `import/import_run_completed` · 9242.26ms · project_name=luma_test_1 phase=finalizing source_name=luma_test_1
- #92 · `import/import_grouping_completed` · 6956.34ms · project_name=luma_test_1 phase=finalizing source_name=luma_test_1
- #91 · `grouping/grouping_completed` · 6956.00ms
- #90 · `grouping/grouping_location_naming_completed` · 6299.00ms
- #16 · `import/initial_manifest_built` · 1913.32ms · project_name=luma_test_1 phase=preparingThumbnails source_name=luma_test_1
- #89 · `grouping/grouping_subgrouping_completed` · 1528.97ms
- #29 · `grouping/grouping_scene_split_completed` · 656.00ms
- #19 · `import/preview_copy_completed` · 205.22ms · project_name=luma_test_1 phase=copyingPreviews source_name=luma_test_1
- #14 · `import/import_source_enumerated` · 135.08ms · project_name=luma_test_1 phase=scanning source_name=luma_test_1

## Recent Errors

无