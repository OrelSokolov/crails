-- Deterministic demo seeds: 6 notes, ids 1..6.
TRUNCATE notes RESTART IDENTITY;
INSERT INTO notes (title, body, color, views, created_at, updated_at) VALUES
('Why Crystal', E'A single binary, millisecond boots and zero GC pauses in production.\n\nCRails brings Rails conventions into the compiled world: the same models, the same templates, the same router — all of it compiled down to native code.', 'violet', 128, '2026-09-28 10:00:00', '2026-09-28 10:00:00'),
('The demo app stack', E'This page went through the whole stack: railties booted the server, action_pack matched the route, active_record loaded the row from PostgreSQL, and action_view rendered the ERB template with partials.', 'sky', 96, '2026-09-29 12:30:00', '2026-09-29 12:30:00'),
('Validations like Rails', E'The title is required and capped at 140 characters — a plain validates in the model. Try saving an empty form: the errors come from the same mechanism as the original.', 'emerald', 64, '2026-09-30 09:15:00', '2026-09-30 09:15:00'),
('View counter', E'Every note opening runs UPDATE notes SET views = views + 1 — the number at the bottom of the card is live.', 'amber', 42, '2026-10-01 18:45:00', '2026-10-01 18:45:00'),
('Flash messages', E'Create or delete a note — the green banner on top is a flash stored in cookies, just like in Rails.', 'rose', 31, '2026-10-02 14:20:00', '2026-10-02 14:20:00'),
('What''s next', E'Next up on the roadmap: PG-backed queues, cache, pubsub and devise authentication for full-blown apps.', 'sky', 12, '2026-10-03 08:00:00', '2026-10-03 08:00:00');
