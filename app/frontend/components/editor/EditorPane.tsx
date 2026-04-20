import CodeMirror from "@uiw/react-codemirror"
import { markdown } from "@codemirror/lang-markdown"
import { EditorView } from "@codemirror/view"
import { oneDark } from "@codemirror/theme-one-dark"
import { useMemo } from "react"

type Props = {
  value: string
  onChange: (next: string) => void
}

export function EditorPane({ value, onChange }: Props) {
  const extensions = useMemo(
    () => [markdown(), EditorView.lineWrapping],
    []
  )

  return (
    <div className="nm-editor-pane">
      <CodeMirror
        value={value}
        height="100%"
        theme={oneDark}
        extensions={extensions}
        onChange={onChange}
        basicSetup={{
          lineNumbers: true,
          highlightActiveLine: true,
          foldGutter: true,
          autocompletion: true,
        }}
      />
    </div>
  )
}
