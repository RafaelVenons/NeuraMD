export function deriveInitialTagOrder(dataset) {
  return [...(dataset.tags || [])]
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((tag) => tag.id)
}

export function resolvePriorityTag(itemTags, activeTagsOrdered, topN) {
  const allowed = topN == null ? activeTagsOrdered : activeTagsOrdered.slice(0, topN)
  const itemTagSet = new Set(itemTags || [])

  for (const tagId of allowed) {
    if (itemTagSet.has(tagId)) return tagId
  }

  return null
}

export function moveTag(activeTagsOrdered, tagId, delta) {
  const currentIndex = activeTagsOrdered.indexOf(tagId)
  if (currentIndex < 0) return activeTagsOrdered

  const nextIndex = currentIndex + delta
  if (nextIndex < 0 || nextIndex >= activeTagsOrdered.length) return activeTagsOrdered

  const reordered = [...activeTagsOrdered]
  const [item] = reordered.splice(currentIndex, 1)
  reordered.splice(nextIndex, 0, item)
  return reordered
}

export function moveTagRelative(activeTagsOrdered, sourceTagId, targetTagId, placement = "before") {
  const sourceIndex = activeTagsOrdered.indexOf(sourceTagId)
  const targetIndex = activeTagsOrdered.indexOf(targetTagId)
  if (sourceIndex < 0 || targetIndex < 0 || sourceIndex === targetIndex) return activeTagsOrdered

  const reordered = [...activeTagsOrdered]
  const [item] = reordered.splice(sourceIndex, 1)
  let insertionIndex

  if (placement === "after") {
    insertionIndex = sourceIndex < targetIndex ? targetIndex : targetIndex + 1
  } else {
    insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
  }

  reordered.splice(insertionIndex, 0, item)
  return reordered
}
