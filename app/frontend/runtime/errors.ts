export type ApiErrorShape = {
  code: string
  message: string
  details?: unknown
}

export class ApiError extends Error {
  readonly status: number
  readonly code: string
  readonly details: unknown

  constructor(status: number, shape: ApiErrorShape) {
    super(shape.message)
    this.status = status
    this.code = shape.code
    this.details = shape.details
  }
}
