# Turbo Streams (порт turbo-rails): подписки страниц через /cable,
# броадкасты из моделей. Требуется ДО моделей — они подмешивают
# Turbo::Broadcastable.

require "turbo_cr"

# Rails берёт ключ из secret_key_base; здесь фиксированный dev-ключ
# (ENV["TURBO_STREAM_KEY"] перекрывает).
Turbo.signed_stream_verifier_key =
  ENV["TURBO_STREAM_KEY"]? || "5c1f4a9b8e2d7c06f31a95b0e8d47c2a6b9d0f3e7a41c58d92b6e0f8a3c7d41b"

# Броадкасты уходят в тот же cable-сервер, что и /cable-эндпоинт.
Turbo.cable_server = DEMO_CABLE

# _later-броадкасты идут через ActiveJob; дефолтный TestAdapter только
# для тестов — включаем встроенный async-пул (Rails' :async).
ActiveJob.adapter = ActiveJob.async_adapter
