export const DSL_OPERATORS = [
  { name: "tag",        hint: "tag:neurociencia",   desc: "Notas com esta tag" },
  { name: "alias",      hint: "alias:DP",           desc: "Notas com este alias" },
  { name: "prop",       hint: "prop:status=done",   desc: "Filtrar por propriedade" },
  { name: "kind",       hint: "kind:reference",     desc: "Tipo de nota" },
  { name: "status",     hint: "status:draft",       desc: "Status da nota" },
  { name: "has",        hint: "has:asset",          desc: "Notas com anexos" },
  { name: "link",       hint: "link:Titulo",        desc: "Notas que linkam para..." },
  { name: "linkedfrom", hint: "linkedfrom:Titulo",  desc: "Notas linkadas de..." },
  { name: "orphan",     hint: "orphan:true",        desc: "Notas sem links" },
  { name: "deadend",    hint: "deadend:true",       desc: "Notas sem links de saida" },
  { name: "created",    hint: "created:>2024-01",   desc: "Data de criacao" },
  { name: "updated",    hint: "updated:<7d",        desc: "Data de atualizacao" },
]

export function matchOperators(partial) {
  if (!partial) return []
  const lower = partial.toLowerCase()
  return DSL_OPERATORS.filter(op => op.name.startsWith(lower))
}

export function getLastWord(text) {
  const words = text.split(/\s+/)
  return words[words.length - 1] || ""
}
