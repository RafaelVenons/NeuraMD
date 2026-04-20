import { createConsumer, type Consumer } from "@rails/actioncable"

let sharedConsumer: Consumer | null = null

export function getCableConsumer(): Consumer {
  if (!sharedConsumer) {
    sharedConsumer = createConsumer()
  }
  return sharedConsumer
}
