

def register_parent(
    client, username="parent1", password="pw123456", display_name="爸爸"
) -> dict:
    r = client.post(
        "/api/v1/auth/register",
        json={
            "username": username,
            "password": password,
            "display_name": display_name,
            "role": "parent",
        },
    )
    return r


def login(client, username, password) -> dict:
    r = client.post(
        "/api/v1/auth/login",
        json={"username": username, "password": password},
    )
    return r


def auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}
