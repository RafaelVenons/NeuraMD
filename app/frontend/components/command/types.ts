export type SearchResult = {
  id: string
  slug: string
  title: string
  snippet: string
  updated_at: string
}

export type SearchMeta = {
  query: string
  page: number
  limit: number
  has_more: boolean
}

export type SearchResponse = {
  results: SearchResult[]
  meta: SearchMeta
}
