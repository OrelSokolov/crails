// Turbo Streams over ActionCable: минимальный аналог cable.js из
// @hotwired/turbo-rails (без npm-сборки). Подключается к /cable,
// подписывается на Turbo::StreamsChannel для каждого
// <turbo-cable-stream-source> на странице и скармливает пришедшие
// turbo-stream документы в Turbo.renderStreamMessage.
//
// Соединение переживает Turbo Drive-навигацию (как cable consumer в
// Rails); на turbo:load пересканирует DOM на новые stream-source.
(function () {
  var ws = null;
  var subscribed = {}; // identifier -> true

  function subscribeEl(el) {
    var name = el.getAttribute("signed-stream-name");
    if (!name) return;
    var identifier = JSON.stringify({
      channel: el.getAttribute("channel") || "Turbo::StreamsChannel",
      signed_stream_name: name
    });
    if (subscribed[identifier]) return;
    subscribed[identifier] = true;
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify({command: "subscribe", identifier: identifier}));
    }
  }

  function rescan() {
    document.querySelectorAll("turbo-cable-stream-source").forEach(subscribeEl);
  }

  function connect() {
    if (!window.WebSocket) return;
    ws = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/cable");
    ws.onopen = function () {
      // после реконнекта подписки на сервере потеряны — подписываем заново
      subscribed = {};
      rescan();
    };
    ws.onmessage = function (event) {
      var frame;
      try { frame = JSON.parse(event.data); } catch (e) { return; }
      if (frame.message && window.Turbo && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(frame.message);
      }
    };
    ws.onclose = function () {
      ws = null;
      setTimeout(connect, 1000);
    };
  }

  rescan();
  connect();
  document.addEventListener("turbo:load", rescan);
})();
