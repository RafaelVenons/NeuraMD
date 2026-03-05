export function wordCount(text) {
  if (!text || !text.trim()) return 0
  return text.trim().split(/\s+/).length
}

export function charCount(text) {
  return (text || "").length
}

export function lineCount(text) {
  if (!text) return 1
  return (text.match(/\n/g) || []).length + 1
}
