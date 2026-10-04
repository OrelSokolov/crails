# active_agent.cr — ActiveAgent

ИИ-агенты для бизнес-приложений: агент = цикл «LLM + инструменты»
(Anthropic Building Effective Agents). Интерфейс с нуля — не порт
Ruby-гема active_agent (гему меньше года); исследование и обоснование
дизайна — корневой PLAN.md, Iteration 17.

Позиционирование: агенты, которые вызывают **типизированные
инструменты поверх данных приложения**, а не исполняют код. Поверхность
атаки = набор инструментов, написанных разработчиком (как REST-API):
LLM выбирает инструмент из allowlist и предлагает JSON-аргументы,
исполнение — обычный код приложения с валидациями AR. Кодинг-агенты
(нужен exec/сандбокс) — вне ниши сознательно.

## Контракты (заморожены)

- `ActiveAgent::Provider` — порт LLM-провайдера (аналог QueueAdapter):
  `chat(ProviderRequest) : ProviderResponse`; опциональная способность
  `StreamingProvider` — `stream_chat(req, & : String ->)`.
  Ошибки API — `ProviderError` (статус + сообщение API, не KeyError).
- `ActiveAgent::Tool` — CRM-контракт: `description` (обязательна —
  ACI-докстринг для LLM) + `input` (типизированные поля → compile-time
  JSON Schema для function calling) + `call : ToolResult`.
  Рантайм-рефлексии нет: аргументы LLM парсятся в типы, известные
  на компиляции.
- `ActiveAgent::Message` — мультимодальный контракт с P0: content-parts
  (текст + изображения), роли system/user/assistant/tool, обмен
  tool_calls. Формат совпадает с проводным у OpenAI и Anthropic.
- `Run`/`Step` — каждый шаг цикла видим: tool_call, аргументы,
  результат, usage. `max_steps` обязателен (stopping condition).

## Провайдеры

Общий движок `Providers::OpenAICompatible` (chat-completions wire,
oracle-locked байт-в-байт) + тонкие реализации со своими ENV,
эндпоинтами, дефолтными моделями и особенностями:

| DSL | Класс | ENV | База по умолчанию |
|---|---|---|---|
| `provider :openai` | `Providers::OpenAI` | OPENAI_API_KEY | api.openai.com/v1 |
| `provider :zai` | `Providers::ZAI` | ZAI_API_KEY | api.z.ai/api/paas/v4 (glm-4.6) |
| `provider :kimi` | `Providers::Kimi` | KIMI_API_KEY / MOONSHOT_API_KEY | api.moonshot.cn/v1 (kimi-k2) |
| `provider :deepseek` | `Providers::DeepSeek` | DEEPSEEK_API_KEY | api.deepseek.com/v1 |
| `provider :lmstudio` | `Providers::LMStudio` | LMSTUDIO_BASE_URL | localhost:1234/v1 |
| `provider :vllm` | `Providers::VLLM` | VLLM_BASE_URL | localhost:8000/v1 |
| `provider :ollama` | `Providers::Ollama` | OLLAMA_BASE_URL | localhost:11434/v1 (OpenAI-compat) |
| `provider :test` | `Providers::Test` | — | scripted, без сети |

Антропный нативный messages-API — следующим заходом. Терминология:
Provider/ProviderRequest/ProviderResponse (не Brain — по решению
автора).

## Статус

- [x] P0 ядро (2026-10-04): контракты Provider/StreamingProvider,
      мультимодальный Message, Tool с compile-time JSON Schema, цикл
      Base#ask (max_steps, compile-time диспетчеризация тулзов, ошибки
      тулзов уходят модели), Run/Step + Usage, Notifications
      "agent.step", Providers::Test. 21/21 спеков.
- [x] OpenAICompatible-движок: wire-оракул — 6 кейсов байт-в-байт
      (tools-запрос, мультимодал, история с tool-результатом, парсинг
      tool_calls/финала/SSE-чанков) + полный HTTP-флоу против
      фейк-сервера; стриминг дельт; stream_options-флаг для локальных.
- [x] Провайдеры zai/kimi/deepseek/lmstudio/vllm/ollama: реестр
      (DSL-имя → класс), спек против фейк-сервера на общем wire,
      env-снапшоты в тестах.
- [~] Live-смоук ZAI (спек запускается при ZAI_API_KEY): wire до
      api.z.ai доходит, авторизация проходит; на аккаунте нет баланса
      (429 «Insufficient balance») — скипается с пометкой до
      пополнения; после — прогнать `crystal spec spec/providers_spec.cr`.
- [ ] Anthropic-провайдер (нативный messages API, tool use blocks)
- [ ] Мосты: стрим-эмиттер → ActionBot/SSE (демо-бот), ask_later
      (ActiveJob), cost/runs-обсервабилити
- [ ] P1: Memory-порт, structured output, ECR-промпты
- [ ] P2: interrupt/resume (HITL на solid_queue), handoffs,
      McpToolSource (MCP-клиент; серверная сторона — action_mcp.cr,
      Iteration 18 — отдельный шард поверх того же контракта Tool)

## Отклонения/решения

- Мост к ActionBot — `Proc(String, Nil)`-эмиттер: шарды НЕ зависят
  друг от друга (обещание №10).
- Workflow-паттерны (chaining/routing/parallelization) — обычный код
  Crystal, без графового DSL (по выводам исследования).
- Реестр тулзов — compile-time case-диспетчер в `tools`-макросе
  (никаких массивов метаклассов/рантайм-рефлексии).
- Wire-имя тулза — последний сегмент имени класса в snake_case:
  `Oracle::CustomerSearch` → "customer_search" (совместимо с MCP).
- Класс-методы Tool поднимаются в includer через `macro included`
  (класс-методы модуля не наследуются через include).
- OpenAI wire: assistant-сообщение всегда пишет `"content":null` при
  tool_calls (шейп документации), запятые в сгенерированном коде —
  внутри веток макроса (парсер не терпит `\n,`).
- Ollama — через официальный OpenAI-совместимый эндпоинт; нативный
  /api/chat — отдельным классом при необходимости.
