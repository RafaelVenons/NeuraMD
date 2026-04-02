// Generates URL-friendly heading slugs matching the server-side
// Headings::ExtractService#generate_slug algorithm.
//
// Handles accented characters via normalize("NFD") + diacritic strip,
// which mirrors ActiveSupport::Inflector.transliterate for Latin scripts.

const DIACRITICS_RE = /[\u0300-\u036f]/g

export function generateHeadingSlug(text, slugCounts = null) {
  let base = text
    .normalize("NFD")
    .replace(DIACRITICS_RE, "")
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .replace(/[\s_]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")

  if (!base) base = "heading"

  if (!slugCounts) return base

  const count = slugCounts.get(base) || 0
  slugCounts.set(base, count + 1)
  return count === 0 ? base : `${base}-${count}`
}
