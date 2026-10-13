# 08: 完成 Resource<T> 加载态迁移

**What to build:** 剩余的 ~14 处手写 sealed 取数加载态统一改用 shared 的 `Resource<T>`；达成 19 调用点统一，旧 sealed 加载态类引用归零。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 全仓旧 sealed 加载态类引用归零（grep）。
- [ ] 每屏只断言"取数四态渲染正确"，不碰内部逻辑。
- [ ] `flutter analyze` + 相关 widget 测试通过。

_— 定位（volatile，仅供本次实施）—_
- `Resource<T>` 定义：`frontend/lib/shared/presentation/resource.dart`
- 现状：仅 5 文件采用，本应替换 19 处；grep `Resource<` 全仓看采用面，grep 旧加载态类名（如各 feature 内的 `XxxState.loading/error`）定位待迁点
