const path = require("node:path")
const { execFileSync } = require("node:child_process")

function runRailsScript(scriptPath, extraEnv = {}) {
  const cwd = path.resolve(__dirname, "../..")
  const output = execFileSync("bin/rails", ["runner", scriptPath], {
    cwd,
    env: {
      ...process.env,
      RAILS_ENV: "test",
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY: process.env.ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY || "0123456789abcdef0123456789abcdef",
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY: process.env.ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY || "abcdef0123456789abcdef0123456789",
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT: process.env.ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT || "1234567890abcdef1234567890abcdef",
      ...extraEnv
    },
    encoding: "utf8"
  }).trim()

  return JSON.parse(output)
}

module.exports = {
  runRailsScript
}
