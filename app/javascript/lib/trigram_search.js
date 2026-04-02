export function normalizeSearchText(value) {
  return (value || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
}

export function trigramVector(value) {
  const compact = `  ${value.replace(/\s+/g, " ")}  `
  const vector = new Map()
  for (let index = 0; index <= compact.length - 3; index += 1) {
    const gram = compact.slice(index, index + 3)
    vector.set(gram, (vector.get(gram) || 0) + 1)
  }
  return vector
}

export function cosineSimilarity(left, right) {
  let dot = 0
  let leftNorm = 0
  let rightNorm = 0

  left.forEach((value, key) => {
    leftNorm += value * value
    dot += value * (right.get(key) || 0)
  })
  right.forEach((value) => {
    rightNorm += value * value
  })

  if (!leftNorm || !rightNorm) return 0
  return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm))
}

export function trigramScore(text, query) {
  const normalizedText = normalizeSearchText(text)
  const normalizedQuery = normalizeSearchText(query)
  if (!normalizedText || !normalizedQuery) return 0
  if (normalizedText.includes(normalizedQuery)) return 1

  const textVector = trigramVector(normalizedText)
  const queryVector = trigramVector(normalizedQuery)
  return cosineSimilarity(textVector, queryVector)
}
