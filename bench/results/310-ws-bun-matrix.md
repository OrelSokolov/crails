# 310-ws-bun-matrix — chat broadcast: CRails fast path vs Bun/Node

Окружение: Intel Core Ultra 7 155H (22 ядра), Linux, bun 1.4, node 26.7.0
(ws 8.21.3), Crystal 1.21.0. Бенч oven-sh/bun verbatim: 32 closed-loop
клиентов, каждый echo-broadcast'ится всем; медиана из 10 секундных сэмплов
(`bench/bun_ws/run_all.sh`).

## Данные (один прогон, одна машина)

| вариант | median msg/s | max | peak RSS |
|---|---|---|---|
| bun-publish (`ws.publishText`) | 2 519 968 | 3 276 423 | 42 MB |
| **crails-cable (action_cable_cr fast path)** | **2 724 800** | **2 883 215** | 95 MB |
| crystal-send (`ws.send` per client) | 1 341 577 | 1 626 950 | 13 MB |
| crystal-frame (frame-once, без батчей) | 1 168 333 | 1 699 547 | 13 MB |
| bun-send (`ws.send` per client) | 419 865 | 488 194 | 46 MB |
| node-ws (ws.send per client) | 248 919 | 300 264 | 62 MB |

crails-cable: `bench/bun_ws/chat-server.crails.cr` — тот же чат на
механизмах action_cable_cr: `CorkWriter.text_frame` (фрейм кодируется один
раз на сообщение, те же байты всем сокетам) + `deliver_frame` в cork-буфер
+ writer-fiber с одним `write` на батч.

## Вывод

Fast path CRails (encode-once + cork + батч-запись) на этом прогоне выше
bun-publish: 2.72M против 2.52M msg/s и ~6.5× bun-send / ~11× node-ws.
Абсолютные числа зависят от состояния машины (раньше bun-publish здесь же
давал 4.17M) — честно сравнивать варианты внутри одного прогона, что и
сделано. Цена — память: 95 MB против 42 MB у bun (cork-буферы по 8 КБ на
соединение + батчи). Write-сисколлы на доставку в этом прогоне не мерялись
(strace под нагрузкой искажает); по дизайню — один `write` на сокет на
цикл флаша, как у uWS cork/drain.

## Почему bun-send/node-ws отстают

Разбор в `action_cable.cr/PLAN.md` (P1.5): per-client `send()` = FFI +
кодирование + фрейм + сисколл на каждого получателя; publish = один вызов,
один encode, нативный fan-out, батч-запись. Наш fast path переносит ровно
эти три идеи.
