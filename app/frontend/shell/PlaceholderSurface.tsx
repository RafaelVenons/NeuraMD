type Props = {
  title: string
  note: string
}

export function PlaceholderSurface({ title, note }: Props) {
  return (
    <section className="nm-shell__placeholder">
      <h1>{title}</h1>
      <p>{note}</p>
    </section>
  )
}
