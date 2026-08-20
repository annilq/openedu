from fastapi import APIRouter

from app.api.routes import auth, children, health, tasks

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(children.router)
api_router.include_router(tasks.router)
api_router.include_router(health.router)
