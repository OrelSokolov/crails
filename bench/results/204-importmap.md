# 204-importmap — рендер importmap-тегов (Iteration 17)

Микробенч порта `importmap.cr` против настоящего `importmap-rails`
2.2.3 + actionview 8.1.4: полный `javascript_importmap_tags` (inline
importmap JSON + modulepreload-линки + import-строка) для карты из 20
`pin` с `to:`, 2-секундный рендер-цикл в одном потоке.

- Скрипты: `importmap.cr/bench/importmap_bench.{cr,rb}` (пара, идентичная
  карта и вывод-контроль).
- Машина: та же, что и остальные замеры (bench/PLAN.md). Ruby 3.4.5,
  Crystal 1.21 (--release). 3 прогона, медиана.

| Сторона | renders/sec (3 прогона) | медиана |
|---|---|---|
| importmap_cr (Crystal, --release) | 165816 / 161108 / 164106 | **164106** |
| importmap-rails 2.2.3 (Ruby) | 14036 / 14086 / 14176 | **14086** |

**~11.6×** по медиане. Вывод байт-в-байт одинаков (оракул
`importmap.cr/oracle/importmap_expected.yml`), ускорение — компиляция
рендера без промежуточных Ruby-объектов (String#build + insertion-order
Hash). На полный стек страницы влияние меньше, чем hello-бенч, т.к.
importmap-теги — один блок в layout; замер фиксирует именно цену хелпера.

Проверка корректности внутри скриптов: рендер содержит
`<script type="importmap"` — иначе abort.
