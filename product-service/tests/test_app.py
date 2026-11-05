
import unittest
from app import app


class ProductServiceTests(unittest.TestCase):

    def setUp(self):
        self.client = app.test_client()

    def test_home(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["service"], "product-service")
        self.assertEqual(len(data["products"]), 2)

    def test_health(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)

    def test_metrics(self):
        response = self.client.get("/metrics")
        self.assertEqual(response.status_code, 200)
        self.assertIn(
            b"microservice_requests_total",
            response.data
        )


if __name__ == "__main__":
    unittest.main()
