type Props = {
  title: string
  note?: string
}

export function PlaceholderTab({ title, note }: Props) {
  return (
    <div className="nm-settings-placeholder">
      <h2>{title}</h2>
      {note ? <p>{note}</p> : null}
    </div>
  )
}
