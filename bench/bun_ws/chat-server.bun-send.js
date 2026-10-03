// Bun bench variant: same chat server, but with per-connection ws.send()
// instead of topic publish() — reproduces the "Bun (send)" row of their chart.
const CLIENTS_TO_WAIT_FOR = parseInt(process.env.CLIENTS_COUNT || "", 10) || 32;
var remainingClients = CLIENTS_TO_WAIT_FOR;
const port = process.env.PORT || 4001;

const clients = [];

const server = Bun.serve({
  port: port,
  websocket: {
    open(ws) {
      clients.push(ws);
      remainingClients--;
      console.log(`${ws.data.name} connected (${remainingClients} remain)`);

      if (remainingClients === 0) {
        console.log("All clients connected");
        setTimeout(() => {
          console.log('Starting benchmark by sending "ready" message');
          for (const client of clients) client.send(`ready`);
        }, 100);
      }
    },
    message(ws, msg) {
      const out = `${ws.data.name}: ${msg}`;
      for (const client of clients) {
        client.send(out);
      }
    },
    close(ws) {
      clients.splice(clients.indexOf(ws), 1);
      remainingClients++;
    },

    perMessageDeflate: false,
  },

  fetch(req, server) {
    if (
      server.upgrade(req, {
        data: {
          name: new URL(req.url).searchParams.get("name") || "Client #" + (CLIENTS_TO_WAIT_FOR - remainingClients),
        },
      })
    )
      return;

    return new Response("Error");
  },
});

console.log(`Waiting for ${remainingClients} clients to connect...\n`, `  http://${server.hostname}:${server.port}/`);
