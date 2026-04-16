from __future__ import annotations

from collections import defaultdict

import pulp

from energy_scheduler.domain import BandAllocation, BandShortfall, BatteryBucketPlan, PlannerInput, PlannerResult


def _bucket_hours(bucket_minutes: int) -> float:
    return bucket_minutes / 60.0


def solve_plan(plan: PlannerInput) -> PlannerResult:
    hours = _bucket_hours(plan.bucket_minutes)
    problem = pulp.LpProblem("energy_scheduler", pulp.LpMaximize)

    scenario_ids = [scenario.scenario_id for scenario in plan.producer.scenarios]
    scenario_tokens = {scenario_id: f"s{index}" for index, scenario_id in enumerate(scenario_ids)}
    scenario_probability = {scenario.scenario_id: scenario.probability for scenario in plan.producer.scenarios}
    solar_by_scenario = {scenario.scenario_id: scenario.solar_generation_kwh for scenario in plan.producer.scenarios}
    bucket_range = range(plan.horizon_buckets)

    import_energy: dict[tuple[str, int], pulp.LpVariable] = {}
    export_energy: dict[tuple[str, int], pulp.LpVariable] = {}
    curtail_energy: dict[tuple[str, int], pulp.LpVariable] = {}
    battery_charge: dict[tuple[str, int], pulp.LpVariable] = {}
    battery_discharge: dict[tuple[str, int], pulp.LpVariable] = {}
    battery_soc: dict[tuple[str, int], pulp.LpVariable] = {}
    reserve_shortfall: dict[tuple[str, int], pulp.LpVariable] = {}

    for scenario_id in scenario_ids:
        scenario_token = scenario_tokens[scenario_id]
        for bucket in bucket_range:
            import_energy[(scenario_id, bucket)] = pulp.LpVariable(f"import_{scenario_token}_{bucket}", lowBound=0)
            export_energy[(scenario_id, bucket)] = pulp.LpVariable(f"export_{scenario_token}_{bucket}", lowBound=0)
            curtail_energy[(scenario_id, bucket)] = pulp.LpVariable(f"curtail_{scenario_token}_{bucket}", lowBound=0)
            charge_limit = plan.battery.max_charge_kw * hours
            discharge_limit = plan.battery.max_discharge_kw * hours
            battery_charge[(scenario_id, bucket)] = pulp.LpVariable(
                f"battery_charge_{scenario_token}_{bucket}",
                lowBound=0,
                upBound=charge_limit,
            )
            battery_discharge[(scenario_id, bucket)] = pulp.LpVariable(
                f"battery_discharge_{scenario_token}_{bucket}",
                lowBound=0,
                upBound=discharge_limit,
            )
            battery_soc[(scenario_id, bucket)] = pulp.LpVariable(
                f"battery_soc_{scenario_token}_{bucket}",
                lowBound=plan.battery.min_soc_kwh,
                upBound=plan.battery.max_soc_kwh,
            )
            reserve_shortfall[(scenario_id, bucket)] = pulp.LpVariable(
                f"reserve_shortfall_{scenario_token}_{bucket}",
                lowBound=0,
            )

    band_energy: dict[tuple[str, str, int], pulp.LpVariable] = {}
    band_shortfall: dict[tuple[str, str], pulp.LpVariable] = {}
    band_tokens = {id(band): f"b{index}" for index, band in enumerate(plan.demand.demand_bands)}

    for band in plan.demand.demand_bands:
        band_token = band_tokens[id(band)]
        active_scenarios = scenario_ids if band.scenario_id is None else [band.scenario_id]
        max_band_energy = band.max_power_kw * hours
        for scenario_id in active_scenarios:
            scenario_token = scenario_tokens[scenario_id]
            band_shortfall[(band.band_id, scenario_id)] = pulp.LpVariable(
                f"band_shortfall_{band_token}_{scenario_token}",
                lowBound=0,
            )
            for bucket in bucket_range:
                if band.earliest_start_index <= bucket <= band.latest_finish_index:
                    band_energy[(band.band_id, scenario_id, bucket)] = pulp.LpVariable(
                        f"band_energy_{band_token}_{scenario_token}_{bucket}",
                        lowBound=0,
                        upBound=max_band_energy,
                    )

    for scenario_id in scenario_ids:
        for bucket in bucket_range:
            if not plan.grid_available:
                problem += import_energy[(scenario_id, bucket)] == 0
            if not plan.producer.export_allowed:
                problem += export_energy[(scenario_id, bucket)] == 0
            if not plan.producer.curtailment_allowed:
                problem += curtail_energy[(scenario_id, bucket)] == 0
            if not plan.battery.grid_charge_allowed:
                problem += battery_charge[(scenario_id, bucket)] <= solar_by_scenario[scenario_id][bucket] + battery_discharge[(scenario_id, bucket)]
            if not plan.battery.export_discharge_allowed:
                problem += export_energy[(scenario_id, bucket)] <= solar_by_scenario[scenario_id][bucket]

            fixed_demand = plan.demand.fixed_demand_kwh[bucket]
            flexible = []
            for band in plan.demand.demand_bands:
                if (band.band_id, scenario_id, bucket) in band_energy:
                    flexible.append(band_energy[(band.band_id, scenario_id, bucket)])

            problem += (
                solar_by_scenario[scenario_id][bucket]
                + import_energy[(scenario_id, bucket)]
                + battery_discharge[(scenario_id, bucket)]
                ==
                fixed_demand
                + pulp.lpSum(flexible)
                + battery_charge[(scenario_id, bucket)]
                + export_energy[(scenario_id, bucket)]
                + curtail_energy[(scenario_id, bucket)]
            )

            previous_soc = plan.battery.initial_soc_kwh if bucket == 0 else battery_soc[(scenario_id, bucket - 1)]
            problem += (
                battery_soc[(scenario_id, bucket)]
                == previous_soc
                + battery_charge[(scenario_id, bucket)] * plan.battery.charge_efficiency
                - battery_discharge[(scenario_id, bucket)] * (1.0 / plan.battery.discharge_efficiency)
            )
            problem += battery_soc[(scenario_id, bucket)] >= plan.battery.emergency_floor_kwh
            problem += reserve_shortfall[(scenario_id, bucket)] >= plan.battery.reserve_target_kwh[bucket] - battery_soc[(scenario_id, bucket)]

    for band in plan.demand.demand_bands:
        active_scenarios = scenario_ids if band.scenario_id is None else [band.scenario_id]
        for scenario_id in active_scenarios:
            active_terms = []
            for bucket in range(max(0, band.start_index), min(plan.horizon_buckets - 1, band.deadline_index) + 1):
                var = band_energy.get((band.band_id, scenario_id, bucket))
                if var is not None:
                    active_terms.append(var)
            served = pulp.lpSum(active_terms)
            problem += served + band_shortfall[(band.band_id, scenario_id)] == band.target_quantity_kwh
            if band.required_level:
                problem += band_shortfall[(band.band_id, scenario_id)] <= band.target_quantity_kwh

    objective_terms = []
    for scenario_id in scenario_ids:
        probability = scenario_probability[scenario_id]
        for bucket in bucket_range:
            objective_terms.append(
                probability
                * (
                    export_energy[(scenario_id, bucket)] * plan.prices.export_prices[bucket]
                    - import_energy[(scenario_id, bucket)] * plan.prices.import_prices[bucket]
                    - (battery_charge[(scenario_id, bucket)] + battery_discharge[(scenario_id, bucket)]) * plan.battery.cycle_cost_czk_per_kwh
                    - reserve_shortfall[(scenario_id, bucket)] * plan.battery.reserve_value_czk_per_kwh[bucket]
                )
            )
        for band in plan.demand.demand_bands:
            if band.scenario_id is not None and band.scenario_id != scenario_id:
                continue
            allocation_terms = []
            for bucket in bucket_range:
                var = band_energy.get((band.band_id, scenario_id, bucket))
                if var is not None:
                    allocation_terms.append(var)
            objective_terms.append(probability * pulp.lpSum(allocation_terms) * band.marginal_value_czk_per_kwh)
            objective_terms.append(probability * (-band_shortfall[(band.band_id, scenario_id)] * band.unmet_penalty_czk_per_kwh))

    problem += pulp.lpSum(objective_terms)
    solver = pulp.PULP_CBC_CMD(msg=False)
    status = problem.solve(solver)
    if pulp.LpStatus[status] != "Optimal":
        raise RuntimeError(f"planner failed with status {pulp.LpStatus[status]}")

    allocations: list[BandAllocation] = []
    shortfalls: list[BandShortfall] = []
    battery_plan: list[BatteryBucketPlan] = []
    summary = defaultdict(float)

    for scenario_id in scenario_ids:
        for bucket in bucket_range:
            charge = float(pulp.value(battery_charge[(scenario_id, bucket)]) or 0.0)
            discharge = float(pulp.value(battery_discharge[(scenario_id, bucket)]) or 0.0)
            soc = float(pulp.value(battery_soc[(scenario_id, bucket)]) or 0.0)
            imported = float(pulp.value(import_energy[(scenario_id, bucket)]) or 0.0)
            exported = float(pulp.value(export_energy[(scenario_id, bucket)]) or 0.0)
            curtailed = float(pulp.value(curtail_energy[(scenario_id, bucket)]) or 0.0)
            battery_plan.append(
                BatteryBucketPlan(
                    scenario_id=scenario_id,
                    bucket_index=bucket,
                    charge_kwh=charge,
                    discharge_kwh=discharge,
                    soc_kwh=soc,
                    import_kwh=imported,
                    export_kwh=exported,
                    curtail_kwh=curtailed,
                )
            )
            summary[f"{scenario_id}.import_kwh"] += imported
            summary[f"{scenario_id}.export_kwh"] += exported

    for band in plan.demand.demand_bands:
        active_scenarios = scenario_ids if band.scenario_id is None else [band.scenario_id]
        for scenario_id in active_scenarios:
            unmet = float(pulp.value(band_shortfall[(band.band_id, scenario_id)]) or 0.0)
            shortfalls.append(BandShortfall(band_id=band.band_id, scenario_id=scenario_id, unmet_kwh=unmet))
            for bucket in bucket_range:
                var = band_energy.get((band.band_id, scenario_id, bucket))
                if var is None:
                    continue
                served = float(pulp.value(var) or 0.0)
                if served > 1e-9:
                    allocations.append(
                        BandAllocation(
                            band_id=band.band_id,
                            scenario_id=scenario_id,
                            bucket_index=bucket,
                            served_kwh=served,
                        )
                    )
                    summary[f"{band.band_id}.served_kwh"] += served

    served_by_bucket = defaultdict(float)
    for allocation in allocations:
        served_by_bucket[(allocation.scenario_id, allocation.bucket_index)] += allocation.served_kwh

    for bucket_plan in battery_plan:
        solar = solar_by_scenario[bucket_plan.scenario_id][bucket_plan.bucket_index]
        fixed = plan.demand.fixed_demand_kwh[bucket_plan.bucket_index]
        served = served_by_bucket[(bucket_plan.scenario_id, bucket_plan.bucket_index)]
        supply = solar + bucket_plan.import_kwh + bucket_plan.discharge_kwh
        use = fixed + served + bucket_plan.charge_kwh + bucket_plan.export_kwh + bucket_plan.curtail_kwh
        if abs(supply - use) > 1e-6:
            raise RuntimeError(
                f"planner produced imbalanced energy flow for {bucket_plan.scenario_id} bucket {bucket_plan.bucket_index}: "
                f"{supply:.6f} != {use:.6f}"
            )

    return PlannerResult(
        objective_value_czk=float(pulp.value(problem.objective) or 0.0),
        battery_plan=battery_plan,
        band_allocations=allocations,
        shortfalls=shortfalls,
        summary=dict(summary),
    )
