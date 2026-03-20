export function tokenize(text) {
  const tokens = []
  const regex = /(\s+|\S+)/g
  let match

  while ((match = regex.exec(text)) !== null) {
    tokens.push(match[0])
  }

  return tokens
}

export function computeWordDiff(original, corrected) {
  const oldTokens = tokenize(original)
  const newTokens = tokenize(corrected)
  const diff = []
  const matrix = Array(oldTokens.length + 1).fill(null).map(() => Array(newTokens.length + 1).fill(0))

  for (let i = 1; i <= oldTokens.length; i++) {
    for (let j = 1; j <= newTokens.length; j++) {
      if (oldTokens[i - 1] === newTokens[j - 1]) {
        matrix[i][j] = matrix[i - 1][j - 1] + 1
      } else {
        matrix[i][j] = Math.max(matrix[i - 1][j], matrix[i][j - 1])
      }
    }
  }

  const reversed = []
  let i = oldTokens.length
  let j = newTokens.length

  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && oldTokens[i - 1] === newTokens[j - 1]) {
      reversed.push({ type: "equal", value: oldTokens[i - 1] })
      i -= 1
      j -= 1
    } else if (j > 0 && (i === 0 || matrix[i][j - 1] >= matrix[i - 1][j])) {
      reversed.push({ type: "insert", value: newTokens[j - 1] })
      j -= 1
    } else {
      reversed.push({ type: "delete", value: oldTokens[i - 1] })
      i -= 1
    }
  }

  reversed.reverse().forEach((item) => {
    const previous = diff[diff.length - 1]
    if (previous && previous.type === item.type) {
      previous.value += item.value
    } else {
      diff.push({ ...item })
    }
  })

  return diff
}
