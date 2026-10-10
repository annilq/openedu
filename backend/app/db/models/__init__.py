"""Centralized ORM layer (feature-first architecture, ADR-0027).

All SQLModel `table=True` entities live here because they reference each other
via foreign keys (Task -> Student/User, TaskQuestion -> Task/Question, ...).
Keeping ORM tables in one package avoids circular imports between feature
packages. Each feature owns its Pydantic schemas, repository and service layer
under `app/features/<name>/`.
"""

from app.db.models.base import (
    get_datetime_utc,
    get_review_due_utc,
    get_usage_date_utc,
)
from app.db.models.class_entity import Class
from app.db.models.conversation import Conversation, Message
from app.db.models.courseware import (
    COURSEWARE_ASSET_MIMES,
    COURSEWARE_STATUSES,
    Courseware,
    CoursewareAsset,
)
from app.db.models.material import (
    CHUNKER_VERSION,
    INDEX_STATES,
    FigureLibrary,
    KnowledgePoint,
    Material,
    MaterialChunk,
    MaterialFolder,
    SceneTemplateConfig,
)
from app.db.models.model_config import ModelConfig
from app.db.models.progress import AnswerRecord, Checkin, WrongQuestion
from app.db.models.question import Question
from app.db.models.task import Task, TaskBase, TaskQuestion
from app.db.models.task_assignment import TaskAssignment
from app.db.models.tutor import TutorLog
from app.db.models.user import User, UserBase

__all__ = [
    "User",
    "UserBase",
    "Class",
    "Task",
    "TaskBase",
    "TaskQuestion",
    "TaskAssignment",
    "Question",
    "ModelConfig",
    "AnswerRecord",
    "Checkin",
    "WrongQuestion",
    "TutorLog",
    "Conversation",
    "Message",
    "Material",
    "MaterialChunk",
    "MaterialFolder",
    "KnowledgePoint",
    "SceneTemplateConfig",
    "FigureLibrary",
    "Courseware",
    "CoursewareAsset",
    "COURSEWARE_STATUSES",
    "COURSEWARE_ASSET_MIMES",
    "CHUNKER_VERSION",
    "INDEX_STATES",
    "get_datetime_utc",
    "get_review_due_utc",
    "get_usage_date_utc",
]
