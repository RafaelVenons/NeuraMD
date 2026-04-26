# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# System PropertyDefinitions that the product depends on. Fresh environments
# bootstrap via db:schema:load + db:seed (data migrations do not replay there),
# so these must be ensured here. Each seeder is idempotent and safe to re-run.
Agents::AvatarPropertyDefinitions.ensure!
Agents::AgenteTagBackfill.ensure!

def ensure_graph_tag(name:, color_hex:)
  Tag.find_or_create_by!(name:) do |tag|
    tag.color_hex = color_hex
    tag.tag_scope = "both"
  end
end

def ensure_graph_note(title:, body:, tags: [])
  note = Note.find_or_create_by!(title:) do |record|
    record.note_kind = "markdown"
    record.detected_language = "pt-BR"
  end

  revision = note.head_revision
  if revision.nil? || revision.content_markdown != body
    revision = NoteRevision.create!(
      note: note,
      content_markdown: body,
      revision_kind: :checkpoint
    )
    note.update_columns(head_revision_id: revision.id)
  end

  tags.each do |tag|
    NoteTag.find_or_create_by!(note:, tag:)
  end

  note
end

def ensure_graph_link(src:, dst:, revision:, hier_role:, tags: [], context: {})
  link = NoteLink.find_or_create_by!(src_note: src, dst_note: dst) do |record|
    record.created_in_revision = revision
    record.hier_role = hier_role
    record.context = context
  end

  if link.hier_role != hier_role || link.created_in_revision_id != revision.id
    link.update!(hier_role:, created_in_revision: revision, context:)
  end

  tags.each do |tag|
    LinkTag.find_or_create_by!(note_link: link, tag:)
  end

  link
end

graph_tags = {
  anatomy: ensure_graph_tag(name: "demo-anatomia", color_hex: "#d97706"),
  cardiology: ensure_graph_tag(name: "demo-cardio", color_hex: "#dc2626"),
  neurology: ensure_graph_tag(name: "demo-neuro", color_hex: "#2563eb"),
  workflow: ensure_graph_tag(name: "demo-fluxo", color_hex: "#059669"),
  reference: ensure_graph_tag(name: "demo-referencia", color_hex: "#7c3aed")
}

graph_notes = [
  { key: :medicine, title: "Demo Grafo Medicina", tags: [:workflow], body: "# Medicina\n\nNó raiz do grafo de demonstração." },
  { key: :cardiology, title: "Demo Cardiologia", tags: [:cardiology], body: "# Cardiologia\n\nEstrutura principal para raciocínio cardiovascular." },
  { key: :neurology, title: "Demo Neurologia", tags: [:neurology], body: "# Neurologia\n\nEstrutura principal para raciocínio neurológico." },
  { key: :anatomy, title: "Demo Anatomia Clínica", tags: [:anatomy, :reference], body: "# Anatomia Clínica\n\nBase estrutural para revisão espacial." },
  { key: :ecg, title: "Demo ECG", tags: [:cardiology], body: "# ECG\n\nInterpretação de ritmo, eixo e condução." },
  { key: :arrhythmia, title: "Demo Arritmias", tags: [:cardiology], body: "# Arritmias\n\nTaquiarritmias e bradiarritmias." },
  { key: :heart_failure, title: "Demo Insuficiência Cardíaca", tags: [:cardiology], body: "# Insuficiência Cardíaca\n\nPerfis hemodinâmicos e manejo." },
  { key: :stroke, title: "Demo AVC", tags: [:neurology], body: "# AVC\n\nSíndromes vasculares e topografia." },
  { key: :headache, title: "Demo Cefaleias", tags: [:neurology], body: "# Cefaleias\n\nPadrões primários e sinais de alerta." },
  { key: :neuro_exam, title: "Demo Exame Neurológico", tags: [:neurology, :workflow], body: "# Exame Neurológico\n\nSequência prática para avaliação." },
  { key: :thorax, title: "Demo Tórax", tags: [:anatomy], body: "# Tórax\n\nPontos de referência e compartimentos." },
  { key: :abdomen, title: "Demo Abdome", tags: [:anatomy], body: "# Abdome\n\nQuadrantes, compartimentos e correlações." },
  { key: :vascular_access, title: "Demo Acesso Vascular", tags: [:workflow], body: "# Acesso Vascular\n\nPassos, material e complicações." },
  { key: :triage, title: "Demo Triagem", tags: [:workflow], body: "# Triagem\n\nPriorização inicial e gatilhos." },
  { key: :red_flags, title: "Demo Sinais de Alarme", tags: [:reference], body: "# Sinais de Alarme\n\nCritérios de gravidade transversais." },
  { key: :electrolytes, title: "Demo Distúrbios Eletrolíticos", tags: [:reference], body: "# Distúrbios Eletrolíticos\n\nPadrões laboratoriais e impacto clínico." },
  { key: :syncope, title: "Demo Síncope", tags: [:cardiology, :neurology], body: "# Síncope\n\nAbordagem diferencial integrada." },
  { key: :delirium, title: "Demo Delirium", tags: [:neurology, :workflow], body: "# Delirium\n\nTriagem e causas precipitantes." },
  { key: :airway, title: "Demo Via Aérea", tags: [:workflow], body: "# Via Aérea\n\nPreparação e sequência prática." },
  { key: :imaging, title: "Demo Estratégia de Imagem", tags: [:reference], body: "# Estratégia de Imagem\n\nQuando pedir exame e por quê." }
]

notes_by_key = graph_notes.each_with_object({}) do |definition, memo|
  memo[definition[:key]] = ensure_graph_note(
    title: definition[:title],
    body: definition[:body],
    tags: definition[:tags].map { |tag_key| graph_tags.fetch(tag_key) }
  )
end

graph_links = [
  [:medicine, :cardiology, "target_is_child", [:workflow]],
  [:medicine, :neurology, "target_is_child", [:workflow]],
  [:medicine, :anatomy, "target_is_child", [:workflow]],
  [:medicine, :triage, "target_is_child", [:workflow]],
  [:medicine, :red_flags, nil, [:reference]],
  [:cardiology, :ecg, "target_is_child", [:cardiology]],
  [:cardiology, :arrhythmia, "target_is_child", [:cardiology]],
  [:cardiology, :heart_failure, "target_is_child", [:cardiology]],
  [:cardiology, :syncope, "same_level", [:cardiology, :neurology]],
  [:cardiology, :electrolytes, nil, [:reference]],
  [:neurology, :stroke, "target_is_child", [:neurology]],
  [:neurology, :headache, "target_is_child", [:neurology]],
  [:neurology, :neuro_exam, "target_is_child", [:workflow]],
  [:neurology, :delirium, "target_is_child", [:workflow]],
  [:neurology, :syncope, "same_level", [:cardiology, :neurology]],
  [:anatomy, :thorax, "target_is_child", [:anatomy]],
  [:anatomy, :abdomen, "target_is_child", [:anatomy]],
  [:triage, :airway, "target_is_child", [:workflow]],
  [:triage, :vascular_access, "target_is_child", [:workflow]],
  [:triage, :imaging, nil, [:reference]],
  [:stroke, :imaging, nil, [:reference]],
  [:arrhythmia, :ecg, "target_is_parent", [:cardiology]],
  [:heart_failure, :electrolytes, nil, [:reference]],
  [:syncope, :ecg, nil, [:cardiology]],
  [:syncope, :stroke, nil, [:neurology]],
  [:delirium, :electrolytes, nil, [:reference]],
  [:thorax, :vascular_access, "same_level", [:anatomy, :workflow]]
]

graph_links.each do |src_key, dst_key, hier_role, tag_keys|
  src_note = notes_by_key.fetch(src_key)
  dst_note = notes_by_key.fetch(dst_key)
  ensure_graph_link(
    src: src_note,
    dst: dst_note,
    revision: src_note.head_revision,
    hier_role: hier_role,
    tags: tag_keys.map { |tag_key| graph_tags.fetch(tag_key) }
  )
end

puts "Seeded graph demo with #{notes_by_key.size} notes and #{graph_links.size} links."
