from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock
from main import app

client = TestClient(app)


def test_status_endpoint():
    response = client.get("/api/status")
    assert response.status_code == 200
    assert response.json()["status"] == "running"


def test_health_endpoint():
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


@patch("main.get_db_connection")
def test_get_users_returns_list(mock_conn):
    mock_cursor = MagicMock()
    mock_cursor.fetchall.return_value = []
    mock_conn.return_value.cursor.return_value = mock_cursor

    response = client.get("/api/users")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


@patch("main.get_db_connection")
def test_create_user_success(mock_conn):
    mock_cursor = MagicMock()
    mock_cursor.fetchone.return_value = [1]
    mock_conn.return_value.cursor.return_value = mock_cursor

    response = client.post("/api/users", json={
        "name": "Test User",
        "email": "test@example.com",
        "status": "active"
    })
    assert response.status_code == 200
    assert response.json()["id"] == 1


def test_create_user_missing_fields():
    response = client.post("/api/users", json={"name": "Incomplete"})
    assert response.status_code == 422