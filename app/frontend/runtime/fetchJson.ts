import { readCsrfToken } from "~/runtime/csrf"
import { ApiError, type ApiErrorShape } from "~/runtime/errors"

type JsonValue = unknown

export type FetchJsonOptions = Omit<RequestInit, "body" | "headers"> & {
  body?: JsonValue
  headers?: Record<string, string>
}

export async function fetchJson<T = unknown>(path: string, options: FetchJsonOptions = {}): Promise<T> {
  const { body, headers: extraHeaders, method = body === undefined ? "GET" : "POST", ...rest } = options

  const headers: Record<string, string> = {
    Accept: "application/json",
    ...extraHeaders,
  }

  if (body !== undefined) {
    headers["Content-Type"] = "application/json"
  }

  if (method !== "GET" && method !== "HEAD") {
    headers["X-CSRF-Token"] = readCsrfToken()
  }

  const response = await fetch(path, {
    ...rest,
    method,
    credentials: "same-origin",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  if (response.status === 204) {
    return undefined as T
  }

  const text = await response.text()
  const payload = text.length > 0 ? safelyParseJson(text) : null

  if (!response.ok) {
    const shape = extractErrorShape(payload, response.statusText)
    throw new ApiError(response.status, shape)
  }

  return payload as T
}

function safelyParseJson(text: string): unknown {
  try {
    return JSON.parse(text)
  } catch {
    return text
  }
}

function extractErrorShape(payload: unknown, fallbackMessage: string): ApiErrorShape {
  if (payload && typeof payload === "object" && "error" in payload) {
    const candidate = (payload as { error: unknown }).error
    if (candidate && typeof candidate === "object") {
      const maybe = candidate as Partial<ApiErrorShape>
      if (typeof maybe.code === "string" && typeof maybe.message === "string") {
        return { code: maybe.code, message: maybe.message, details: maybe.details }
      }
    }
  }
  return { code: "unknown", message: fallbackMessage || "Unexpected error" }
}
