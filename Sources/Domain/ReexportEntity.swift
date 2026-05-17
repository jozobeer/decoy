// Entity module を Domain 経由で透過的に使えるようにするための facade。
// `import Domain` 側に Clip / Frame / OutputMode などの data 型も含めて
// 取り回せるので、Phase 1b の Entity 切り出しを既存呼び出し箇所に
// 波及させずに済む。lyra の `Sources/Domain/+ReexportEntity.swift` と
// 同じ手法。
@_exported import Entity
