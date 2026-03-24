async function signIn(page, credentials) {
  await page.goto("/users/sign_in")
  await page.getByLabel("E-mail").fill(credentials.email)
  await page.getByLabel("Senha").fill(credentials.password)
  await Promise.all([
    page.waitForURL((url) => !url.pathname.startsWith("/users/sign_in")),
    page.getByRole("button", { name: "Entrar" }).click()
  ])
}

module.exports = {
  signIn
}
