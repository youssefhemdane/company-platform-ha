from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import psycopg2
from datetime import datetime
from pydantic import BaseModel
from typing import Optional

app = FastAPI()


def get_db_connection():
    return psycopg2.connect(
        host="postgres",
        database="companydb",
        user="admin",
        password="admin123"
    )


class UserCreate(BaseModel):
    name: str
    email: str
    status: Optional[str] = "active"


class UserUpdate(BaseModel):
    name: Optional[str] = None
    email: Optional[str] = None
    status: Optional[str] = None


app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
def serve_index():
    return FileResponse("static/index.html")


@app.get("/api/status")
def status():
    return {
        "status": "running",
        "message": "Company Platform API",
        "timestamp": datetime.now().isoformat()
    }


@app.get("/api/health")
def health():
    return {"status": "healthy"}


@app.get("/api/users")
def get_users():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT id, name, email, status, created_at FROM users ORDER BY id")
        rows = cur.fetchall()
        cur.close()
        conn.close()
        return [
            {
                "id": r[0],
                "name": r[1],
                "email": r[2],
                "status": r[3],
                "created_at": r[4].isoformat() if r[4] else None
            }
            for r in rows
        ]
    except Exception:
        return []


@app.post("/api/users")
def create_user(user: UserCreate):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO users (name, email, status) VALUES (%s, %s, %s) RETURNING id",
            (user.name, user.email, user.status)
        )
        user_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()
        return {"id": user_id, "message": "User created successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.put("/api/users/{user_id}")
def update_user(user_id: int, user: UserUpdate):
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        update_fields = []
        values = []

        if user.name is not None:
            update_fields.append("name = %s")
            values.append(user.name)
        if user.email is not None:
            update_fields.append("email = %s")
            values.append(user.email)
        if user.status is not None:
            update_fields.append("status = %s")
            values.append(user.status)

        if not update_fields:
            raise HTTPException(status_code=400, detail="No fields to update")

        values.append(user_id)
        query = f"UPDATE users SET {', '.join(update_fields)} WHERE id = %s RETURNING id"

        cur.execute(query, values)
        updated = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        if not updated:
            raise HTTPException(status_code=404, detail="User not found")

        return {"id": user_id, "message": "User updated successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.delete("/api/users/{user_id}")
def delete_user(user_id: int):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("DELETE FROM users WHERE id = %s RETURNING id", (user_id,))
        deleted = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        if not deleted:
            raise HTTPException(status_code=404, detail="User not found")

        return {"message": "User deleted successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))