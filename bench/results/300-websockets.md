# 300-websockets — удержанные коннекты и broadcast (Iteration 4)

Окружение: Intel Core Ultra 7 155H (22 ядра), 32 GB RAM, Linux 6.19.14.
CRails: Crystal 1.21.0, `action_cable_cr` Server (fiber-per-connection,
HTTP::WebSocket stdlib), pubsub Async in-process. Референс: Rails 8.1.4
ActionCable (adapter async) + Puma 8.0.2 (Ruby 3.4.5). Клиент:
`bench/loadgen/ws_load.cr` — Crystal fiber-клиенты, Rails-JSON-протокол
(welcome → subscribe → confirm_subscription → {identifier, message}),
с Origin-заголовком (Rails отклоняет коннекты без Origin). 300 клиентов,
бёрдcast-бёрст 100 сообщений всем, 3 прогона, медиана.

## Данные

### CRails (action_cable_cr)
| clients | subscribed | msgs delivered | burst s | msgs/sec | handshake s |
|---------|-----------|----------------|---------|----------|-------------|
| 300     | 300/300   | 30000/30000    | 0.115   | 261210   | 0.104       |

RSS при 300 удержанных коннектах: 87 344 KB (~290 KB/коннект, после
3×30k доставок). Потерь нет.

### Rails ActionCable (Puma)
| clients | subscribed | msgs delivered | burst s | msgs/sec | handshake s |
|---------|-----------|----------------|---------|----------|-------------|
| 300     | 300/300   | 30000/30000    | 4.501   | 6666     | 4.808       |

RSS при 300 удержанных коннектах: 122 824 KB (~409 KB/коннект).
Потерь нет.

## Вывод

CRails: ~260k сообщений/сек бродкаста при 300 коннектах против ~6.7k
у Rails ActionCable (~39×), хендшейк подписки 0.1 s против 3.6–4.9 s
(~40×), память на коннект 290 KB против 409 KB. Потерь нет у обоих.
Цель «100k коннектов на процессе» — не проверена (ulimit/память),
следующий шаг.

Конфигурации: `ws_bench.sh 3300 /tmp/crails_ws.pid crails_ws` /
`ws_bench.sh 3400 /tmp/rails_ws.pid rails_ws`.
