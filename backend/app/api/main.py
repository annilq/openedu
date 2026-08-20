from fastapi import APIRouter

from app.api.routes import (
    auth,
    children,
    health,
    mastery,
    review,
    tasks,
    tutor,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(children.router)
api_router.include_router(tasks.router)
api_router.include_router(review.router)
api_router.include_router(mastery.router)
api_router.include_router(tutor.router)
api_router.include_router(health.router)
