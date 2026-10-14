# 11: 场景编辑器归位为弹窗，并立下编辑形态规则

**What to build:** 打开知识点场景编辑器是**浮层弹窗**，而不是被硬夹成窄条的整页——它本来就是按弹窗尺寸设计的。同时把「什么会铺满、什么会浮起」写成明文规则，之后新增编辑动作有据可依，用户也不必猜点下去是换页还是浮起一层。

**Blocked by:** 03（返回栈：编辑器不再需要自己声明回落目标）

**Status:** done

## 验收

- [x] 场景编辑器以弹窗形态打开，尺寸沿用其原本设计的宽度（560，经 `ShadDialog` + `ConstrainedBox(maxWidth:560)`）
- [x] 关闭后回到来源页（场景库详情）——弹窗是覆盖层、不是 `TeacherPage`，`pop` 即回落来源页
- [x] 关闭时仍作废场景库清单缓存（`_openEditor` 的 `onBack` 调 `ref.invalidate(sceneLibraryProvider)`，既有行为未丢）
- [x] 规则写入前端硬规则文档：`docs/adr/0059-parent-navigation-single-page-state.md` 新增「编辑形态决策规则」段（整页 / 弹窗 / 壳内换页 三档 + 纪律 + 场景编辑器显式例外）
- [x] 按规则复核现有三处编辑形态（模型 / 课件章节 / 课件）：三处均符合规则（模型=`showShadDialog` 弹窗 / 课件章节=`showDialog` 短表单 / 课件=`Navigator.push` 重型编辑器），**无后续票**
- [x] widget 测试：`scene_library_t04_test.dart` 新增「点卡片以 ShadDialog 浮层打开编辑器，关闭回落详情页」；缓存失效在 `teacher_nav_single_source_test.dart` 的 T02→11 组以代码级断言覆盖（`_openEditor` 含 `ref.invalidate(sceneLibraryProvider)`）

## 纪律

- 本票只归位**场景编辑器这一处**，不批量重排其它弹窗（模型/课件章节已是弹窗、课件编辑符合整页规则，均不动）。
- 弹窗仍需满足既有可聚焦要求：不是可点区域就不进焦点树，但弹窗内的控件必须可 Tab、可 Enter。

## 落地要点

- 删除 `SceneLibraryEditorPage`（`teacher_pages.dart` 的 `TeacherPage` 分支）+ `page_labels.dart` 的密封 switch 分支 + `home_screen.dart` 的整页 case 与 `onOpenKp`，改为由 `scene_library_detail_view.dart` 的 `_openEditor` 经 `showShadDialog` + `ShadDialog` 打开 `KnowledgePointSceneEditor`。
- `_InstanceCard.onOpen` 改为携带 `SceneLibraryKpRef`，由详情页统一开弹窗；`_openEditor(onBack: …)` 先作废缓存再 `Navigator.of(dialogCtx).pop()`。
- `KnowledgePointSceneEditor.onBack` 注释同步（不再经 `_go(back)`，由调用方决定回落动作）。
