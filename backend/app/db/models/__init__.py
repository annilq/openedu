"""Centralized ORM layer (feature-first architecture, ADR-0027).

All SQLModel `table=True` entities live here because they reference each other
via foreign keys (Task -> Child/User, TaskQuestion -> Task/Question, ...).
Keeping ORM tables in one package avoids circular imports between feature
packages. Each feature owns its Pydantic schemas, repository and service layer
under `app/features/<name>/`.
"""

from app.db.models.base import (
    get_datetime_utc,
    get_review_due_utc,
    get_usage_date_utc,
)
from app.db.models.conversation import Conversation, Message
from app.db.models.model_config import ModelConfig
from app.db.models.progress import AnswerRecord, Checkin, WrongQuestion
from app.db.models.question import Question
from app.db.models.task import Task, TaskBase, TaskQuestion
from app.db.models.tutor import TutorLog
from app.db.models.user import User, UserBase

__all__ = [
    "User",
    "UserBase",
    "Task",
    "TaskBase",
    "TaskQuestion",
    "Question",
    "ModelConfig",
    "AnswerRecord",
    "Checkin",
    "WrongQuestion",
    "TutorLog",
    "Conversation",
    "Message",
    "get_datetime_utc",
    "get_review_due_utc",
    "get_usage_date_utc",
]
