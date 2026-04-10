# Trace Summary

- Generated: 2026-04-10T16:54:04Z
- Trace: `/Users/qinkan/Library/Application Support/Luma/Diagnostics/runtime-latest.jsonl`
- Session: `736A80E5-095B-4A4F-9DB9-0B43F7ADDE40`
- Records: 272
- Parse failures: 0
- Time range: 2026-04-10T16:52:08Z -> 2026-04-10T16:53:43Z

## Levels

- `metric` · 166
- `info` · 106

## Categories

- `state` · 115
- `grouping` · 71
- `interaction` · 50
- `culling` · 15
- `import` · 14
- `app` · 6
- `project` · 1

## Top Events

- 115x · `metric` · `state` · `derived_state_rebuilt`
- 59x · `info` · `grouping` · `burst_candidate`
- 16x · `metric` · `interaction` · `group_selected`
- 15x · `info` · `culling` · `decision_updated`
- 15x · `info` · `interaction` · `key_command_handled`
- 15x · `metric` · `interaction` · `selection_moved`
- 5x · `info` · `grouping` · `scene_cut_candidate`
- 5x · `info` · `import` · `import_phase_changed`
- 4x · `metric` · `interaction` · `asset_selected`
- 3x · `info` · `app` · `app_activation_attempted`

## Slow Metrics

- `import/import_completed` · count=1 · avg=8929.11ms · p50=8929.11ms · p95=8929.11ms · max=8929.11ms
- `grouping/group_names_refreshed` · count=1 · avg=6078.39ms · p50=6078.39ms · p95=6078.39ms · max=6078.39ms
- `grouping/grouping_background_location_naming_completed` · count=2 · avg=5233.00ms · p50=6078.00ms · p95=6078.00ms · max=6078.00ms
- `import/import_run_completed` · count=1 · avg=4405.49ms · p50=4405.49ms · p95=4405.49ms · max=4405.49ms
- `import/import_grouping_completed` · count=1 · avg=2014.50ms · p50=2014.50ms · p95=2014.50ms · max=2014.50ms
- `grouping/grouping_completed` · count=1 · avg=2014.00ms · p50=2014.00ms · p95=2014.00ms · max=2014.00ms
- `import/initial_manifest_built` · count=1 · avg=1986.61ms · p50=1986.61ms · p95=1986.61ms · max=1986.61ms
- `grouping/grouping_location_naming_completed` · count=1 · avg=1417.00ms · p50=1417.00ms · p95=1417.00ms · max=1417.00ms
- `grouping/grouping_subgrouping_completed` · count=1 · avg=1413.52ms · p50=1413.52ms · p95=1413.52ms · max=1413.52ms
- `grouping/grouping_scene_split_completed` · count=1 · avg=596.00ms · p50=596.00ms · p95=596.00ms · max=596.00ms

## Hotspot Budgets

- `import/import_grouping_completed` · budget=1000ms · count=1 · breaches=1 · p95=2014.50ms · max=2014.50ms · breach
- `import/initial_manifest_built` · budget=1000ms · count=1 · breaches=1 · p95=1986.61ms · max=1986.61ms · breach
- `app/bootstrap_completed` · budget=80ms · count=1 · breaches=0 · p95=31.33ms · max=31.33ms · ok
- `state/derived_state_rebuilt` · budget=8ms · count=115 · breaches=0 · p95=0.82ms · max=1.10ms · ok
- `interaction/group_selected` · budget=16ms · count=16 · breaches=0 · p95=0.73ms · max=0.78ms · ok
- `interaction/asset_selected` · budget=8ms · count=4 · breaches=0 · p95=0.14ms · max=0.14ms · ok

## Slow Chains

- #7 · `app/bootstrap_completed` · total=31.33ms · budget=150ms · max-stage=31.33ms · stages=1 · project_name=luma_test_1 selected_group_id=all selected_asset_id=D4FCF0FE-D8B2-4108-A7E1-DA46AF618CB9
  - app/bootstrap_completed 31.33ms
- #249 · `interaction/group_selected` · total=2.08ms · budget=120ms · max-stage=0.83ms · stages=5 · project_name=luma_test_1 group_id=CDE450B5-0DA6-4CAE-B911-A1EF81389E98 selected_group_id=CDE450B5-0DA6-4CAE-B911-A1EF81389E98 selected_asset_id=E622B36A-506C-412A-AB80-7FB00A9B3952
  - interaction/group_selected 0.55ms
  - state/derived_state_rebuilt 0.83ms
  - interaction/selection_moved 0.06ms
  - state/derived_state_rebuilt 0.62ms
  - interaction/selection_moved 0.02ms
- #231 · `interaction/group_selected` · total=1.90ms · budget=120ms · max-stage=0.82ms · stages=5 · project_name=luma_test_1 group_id=4BBF0AE2-882E-44D3-9861-832A54040FF9 selected_group_id=4BBF0AE2-882E-44D3-9861-832A54040FF9 selected_asset_id=2D28164A-4805-4581-924D-341ABC7DFB9B
  - interaction/group_selected 0.35ms
  - state/derived_state_rebuilt 0.82ms
  - interaction/selection_moved 0.11ms
  - state/derived_state_rebuilt 0.60ms
  - interaction/selection_moved 0.02ms
- #258 · `interaction/group_selected` · total=1.64ms · budget=120ms · max-stage=1.10ms · stages=3 · project_name=luma_test_1 group_id=21B757E0-3C92-4E58-A8B8-ECAACE591B9C selected_group_id=21B757E0-3C92-4E58-A8B8-ECAACE591B9C selected_asset_id=BFEBF8AD-6695-4132-A31E-2B4612D1CB92
  - interaction/group_selected 0.44ms
  - state/derived_state_rebuilt 1.10ms
  - interaction/selection_moved 0.10ms
- #199 · `interaction/group_selected` · total=0.78ms · budget=120ms · max-stage=0.78ms · stages=1 · project_name=luma_test_1 group_id=1C2FEF69-D429-48FF-A55E-42CA8B9A5CDF selected_group_id=1C2FEF69-D429-48FF-A55E-42CA8B9A5CDF selected_asset_id=7132E6C4-4210-4EA2-9636-2A40B600D0D7
  - interaction/group_selected 0.78ms
- #198 · `interaction/group_selected` · total=0.73ms · budget=120ms · max-stage=0.73ms · stages=1 · project_name=luma_test_1 group_id=A7CFAC1D-EA7C-4D4B-BA47-EC6A2EBFFE88 selected_group_id=A7CFAC1D-EA7C-4D4B-BA47-EC6A2EBFFE88 selected_asset_id=DC31891D-DE91-4941-87AE-FC75F50FB232
  - interaction/group_selected 0.73ms
- #203 · `interaction/group_selected` · total=0.71ms · budget=120ms · max-stage=0.71ms · stages=1 · project_name=luma_test_1 group_id=3D968A3E-B9BE-4834-B816-4045CD332C79 selected_group_id=3D968A3E-B9BE-4834-B816-4045CD332C79 selected_asset_id=88DE5F8D-B399-4E6C-B8F9-E6A5D64B7951
  - interaction/group_selected 0.71ms
- #204 · `interaction/group_selected` · total=0.55ms · budget=120ms · max-stage=0.55ms · stages=1 · project_name=luma_test_1 group_id=8105AFD7-6E94-4862-B034-488522EE5596 selected_group_id=8105AFD7-6E94-4862-B034-488522EE5596 selected_asset_id=5842857E-609E-4670-AC67-9209BADB37CA
  - interaction/group_selected 0.55ms
- #201 · `interaction/group_selected` · total=0.55ms · budget=120ms · max-stage=0.55ms · stages=1 · project_name=luma_test_1 group_id=8105AFD7-6E94-4862-B034-488522EE5596 selected_group_id=8105AFD7-6E94-4862-B034-488522EE5596 selected_asset_id=5842857E-609E-4670-AC67-9209BADB37CA
  - interaction/group_selected 0.55ms
- #200 · `interaction/group_selected` · total=0.50ms · budget=120ms · max-stage=0.50ms · stages=1 · project_name=luma_test_1 group_id=2E13ED5C-10A6-47AD-A4C5-885A4F9B4370 selected_group_id=2E13ED5C-10A6-47AD-A4C5-885A4F9B4370 selected_asset_id=C0B9E1BB-B28F-4E9C-AD8B-2DDAD8D8D913
  - interaction/group_selected 0.50ms

## Slow Samples

- #95 · `import/import_completed` · 8929.11ms · project_name=luma_test_1 selected_group_id=all selected_asset_id=CE28C065-F60F-43C2-B9AD-0FDBA3E7A796
- #192 · `grouping/group_names_refreshed` · 6078.39ms · project_name=luma_test_1 selected_group_id=all selected_asset_id=CE28C065-F60F-43C2-B9AD-0FDBA3E7A796
- #190 · `grouping/grouping_background_location_naming_completed` · 6078.00ms
- #92 · `import/import_run_completed` · 4405.49ms · project_name=luma_test_1 phase=finalizing source_name=luma_test_1
- #189 · `grouping/grouping_background_location_naming_completed` · 4388.00ms
- #91 · `import/import_grouping_completed` · 2014.50ms · project_name=luma_test_1 phase=finalizing source_name=luma_test_1
- #90 · `grouping/grouping_completed` · 2014.00ms
- #15 · `import/initial_manifest_built` · 1986.61ms · project_name=luma_test_1 phase=preparingThumbnails source_name=luma_test_1
- #89 · `grouping/grouping_location_naming_completed` · 1417.00ms
- #88 · `grouping/grouping_subgrouping_completed` · 1413.52ms

## Recent Errors

无