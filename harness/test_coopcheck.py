import unittest

from coopcheck import parse_result


class CoopResultTests(unittest.TestCase):
    def sample(self, finished=1, map_number=1):
        bots = ["bot {} kills 2 deaths 1".format(i) for i in range(1, 5)]
        return "\n".join(bots + [
            "end tic 350 finished {} secrets 0 of 3 sum 123 map E1M{}".format(finished, map_number)
        ])

    def test_actual_exit(self):
        result = parse_result(self.sample(), 1, 350)
        self.assertTrue(result["finished"])
        self.assertEqual((result["kills"], result["deaths"]), (8, 4))

    def test_time_limit_is_not_a_completion(self):
        self.assertFalse(parse_result(self.sample(finished=0), 1, 350)["finished"])

    def test_abandonment_cannot_be_reported_as_completion(self):
        with self.assertRaises(ValueError):
            parse_result("league cutoff 1\n" + self.sample(), 1, 350)
        self.assertTrue(parse_result("league cutoff 1\n" + self.sample(finished=0), 1, 350)["gaveup"])

    def test_wrong_map_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_result(self.sample(map_number=2), 1, 350)

    def test_missing_players_are_rejected(self):
        with self.assertRaises(ValueError):
            parse_result("\n".join(self.sample().splitlines()[1:]), 1, 350)

    def test_out_of_range_tic_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_result(self.sample(), 1, 349)


if __name__ == "__main__":
    unittest.main()
