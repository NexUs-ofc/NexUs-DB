import unittest
from collections import defaultdict
from datetime import date

from script.dataload.src.bi import SimulacaoBI, montar_catalogo


class StockMovementSimulationTest(unittest.TestCase):
    def test_simulation_preserves_every_history_item_with_zero_balance(self):
        sequences = defaultdict(int)

        def allocate(table, count):
            start = sequences[table] + 1
            sequences[table] += count
            return list(range(start, start + count))

        foods = {index: sku for index, sku in enumerate(montar_catalogo(), start=1)}
        plans = [(1, "Ceris", 19.90), (2, "Enterprise", 49.90), (3, "Exclusive", 99.90)]
        simulation = SimulacaoBI(date(2026, 10, 25), foods, plans, allocate).gerar()
        items = {item["id"]: item for item in simulation.pg["pantry_item"]}

        self.assertEqual(len(items), len(simulation.pg["pantry_item"]))
        self.assertGreater(len(simulation.hist), 0)
        for movement in simulation.hist:
            item = items[movement["pantry_item_id"]]
            self.assertEqual(item["quantity"], 0)
            self.assertIn(movement["event_type"], {"CONSUMED", "DISCARDED"})
            self.assertGreater(movement["quantity"], 0)
            self.assertLessEqual(item["created_at"], movement["event_date"])
            self.assertNotIn("profile_id", movement)
            self.assertNotIn("food_id", movement)
            self.assertNotIn("consumed_quantity", movement)
            self.assertNotIn("discarded_quantity", movement)


if __name__ == "__main__":
    unittest.main()
