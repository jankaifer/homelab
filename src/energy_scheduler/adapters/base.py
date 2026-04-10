from __future__ import annotations

from abc import ABC, abstractmethod

from energy_scheduler.domain import BatteryState, DemandPlanInput, PriceSeries, ProducerForecast


class PriceAdapter(ABC):
    @abstractmethod
    def get_prices(self, horizon_buckets: int) -> PriceSeries:
        raise NotImplementedError


class ProducerAdapter(ABC):
    @abstractmethod
    def get_forecast(self, horizon_buckets: int) -> ProducerForecast:
        raise NotImplementedError


class BatteryAdapter(ABC):
    @abstractmethod
    def get_battery(self, horizon_buckets: int) -> BatteryState:
        raise NotImplementedError


class DemandAdapter(ABC):
    @abstractmethod
    def get_demand(self, horizon_buckets: int, bucket_minutes: int) -> DemandPlanInput:
        raise NotImplementedError
