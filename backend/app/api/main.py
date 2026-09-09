from fastapi import APIRouter

from app.features.ai.router import router as ai_router
from app.features.assistant.router import router as assistant_router
from app.features.auth.router import router as auth_router
from app.features.children.router import router as children_router
from app.features.health.router import router as health_router
from app.features.mastery.router import router as mastery_router
from app.features.model_management.router import router as model_management_router
from app.features.questions.router import router as questions_router
from app.features.review.router import router as review_router
from app.features.tasks.router import router as tasks_router
from app.features.tutor.router import router as tutor_router

api_router = APIRouter()
api_router.include_router(auth_router)
api_router.include_router(children_router)
api_router.include_router(tasks_router)
api_router.include_router(review_router)
api_router.include_router(mastery_router)
api_router.include_router(tutor_router)
api_router.include_router(questions_router)
api_router.include_router(model_management_router)
api_router.include_router(ai_router)
api_router.include_router(assistant_router)
api_router.include_router(health_router)
