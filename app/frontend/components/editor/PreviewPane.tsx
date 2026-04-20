import { useMemo } from "react"

import { renderMarkdown } from "~/components/editor/markdown"

type Props = {
  content: string
}

export function PreviewPane({ content }: Props) {
  const html = useMemo(() => renderMarkdown(content), [content])
  return (
    <article
      className="nm-preview-pane"
      dangerouslySetInnerHTML={{ __html: html }}
    />
  )
}
