const VIDEO_EXTS = /\.(mp4|webm|mov|ogv)(\?|$)/i
const AUDIO_EXTS = /\.(mp3|ogg|wav|flac|aac)(\?|$)/i
const PDF_EXT = /\.pdf(\?|$)/i

function replaceWithVideo(img) {
  const container = document.createElement("figure")
  container.className = "media-container"
  const video = document.createElement("video")
  video.src = img.src
  video.controls = true
  video.preload = "metadata"
  if (img.alt) video.title = img.alt
  video.onerror = () => showError(container, img.alt, img.src)
  container.appendChild(video)
  img.replaceWith(container)
}

function replaceWithAudio(img) {
  const container = document.createElement("figure")
  container.className = "media-container"
  const audio = document.createElement("audio")
  audio.src = img.src
  audio.controls = true
  audio.preload = "metadata"
  if (img.alt) audio.title = img.alt
  audio.onerror = () => showError(container, img.alt, img.src)
  container.appendChild(audio)
  img.replaceWith(container)
}

function replaceWithPdf(img) {
  const container = document.createElement("figure")
  container.className = "media-container"
  const iframe = document.createElement("iframe")
  iframe.src = img.src
  iframe.title = img.alt || "PDF"
  iframe.sandbox = "allow-same-origin"
  iframe.loading = "lazy"
  iframe.onerror = () => showError(container, img.alt, img.src)
  container.appendChild(iframe)
  img.replaceWith(container)
}

function enhanceImage(img) {
  img.loading = "lazy"
  img.onerror = () => {
    const error = document.createElement("div")
    error.className = "media-error"
    error.textContent = img.alt
      ? `Imagem nao disponivel: ${img.alt}`
      : "Imagem nao disponivel"
    img.replaceWith(error)
  }
}

function showError(container, alt, src) {
  container.innerHTML = ""
  const error = document.createElement("div")
  error.className = "media-error"
  error.textContent = alt
    ? `Midia nao disponivel: ${alt}`
    : `Midia nao disponivel: ${src}`
  container.appendChild(error)
}

export const mediaEmbedRenderer = {
  name: "media-embed",
  type: "sync",
  selector: "img",
  dependencies: ["embed-loader"],
  limits: { maxElements: 50 },
  fallbackHTML: (el) => `<span class="media-fallback">[Midia: ${el.alt || el.src || ""}]</span>`,
  process(element) {
    const src = element.getAttribute("src") || ""

    if (VIDEO_EXTS.test(src)) {
      replaceWithVideo(element)
    } else if (AUDIO_EXTS.test(src)) {
      replaceWithAudio(element)
    } else if (PDF_EXT.test(src)) {
      replaceWithPdf(element)
    } else {
      enhanceImage(element)
    }
  }
}
