export function buildWikilinkMarkup({ display, role, uuid, headingSlug, blockId }) {
  const rolePrefix = role ? `${role}:` : ""
  const fragment = headingSlug ? `#${headingSlug}` : blockId ? `^${blockId}` : ""
  return `[[${display}|${rolePrefix}${uuid}${fragment}]]`
}
