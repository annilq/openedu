"""课件 feature（ADR-0067）：知识点驱动的课堂讲解环节（备课 + 讲课）。

两条并行线各写各的模块，**不得共用文件**（ADR-0067 §6.4 约定 1）：

- 素材线（切片 2）：``asset_service.py`` / ``asset_router.py`` / ``asset_schemas.py``
- 课件线（切片 3）：``service.py`` / ``router.py`` / ``schemas.py``

``schemas.py`` 与 ``asset_schemas.py`` 是**契约文件**（批次 0 已钉形状），
只可补字段说明、不可改字段语义——改了就要同步前端 model。
"""
