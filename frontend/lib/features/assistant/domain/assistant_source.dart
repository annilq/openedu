/// 答疑引用落点（后端 `rag_sources` DATA 帧的载荷项）。
///
/// 一条即「答案下方『参考来源』里的一个可点开来源」：命中并实际注入 prompt 的
/// 资料片段溯源。来自 [app/domain/tutor.py] 的 [RAGSource.to_dict]。
class RagSource {
  final String materialId;
  final String materialName;
  final String chunkId;
  final String snippet;

  const RagSource({
    required this.materialId,
    required this.materialName,
    required this.chunkId,
    required this.snippet,
  });

  factory RagSource.fromJson(Map<String, dynamic> json) => RagSource(
        materialId: '${json['material_id'] ?? ''}',
        materialName: '${json['material_name'] ?? ''}',
        chunkId: '${json['chunk_id'] ?? ''}',
        snippet: '${json['snippet'] ?? ''}',
      );
}
