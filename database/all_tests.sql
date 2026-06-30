-- ============================================================
-- Folgender Code beschreibt die praktische Umsetzung der in der projektarbeit angeführten Methodik,
-- um die Ergebnisse nachvollziehen zu können und sie reproduzierbar zu machen. Hierbei wird der Code nur 
-- auf der Dev-maschine getestet, da diese genau für solche Performance Simulationen vorgesehen ist.
--
-- Hierbei macht es jedoch wenig Sinn, die komplette Datei auf einmal auszuführen, da sich die Tests gegenseitig 
-- beeinflussen, weil sich Indexe, Cache‑Zustände und Tabellenzustände während der Ausführung ändern.
-- Damit würde man keine sauberen Messwerte bekommen und die Unterschiede zwischen Seq Scan, Index Scan 
-- und Bitmap Scan wären verwischt.
--
-- Deshalb ist diese Datei als Anleitung zu verstehen, welche SQL-Befehle nacheinander in PostSQL 
-- Umgebung ausgeführt werden sollten (einzeln).
--
-- Um sie ausführen zu können, in der Dev Umgebung zuvor
--   > sudo -i -u postgres
--   > psql 
-- ausführen. 
-- ============================================================




-- ============================================================
-- 1) Tabelle erzeugen
-- ============================================================

DROP TABLE IF EXISTS predictions_test;

CREATE TABLE predictions_test (
    id SERIAL PRIMARY KEY,
    image_id TEXT NOT NULL,
    prediction INT NOT NULL,
    confidence FLOAT NOT NULL,
    model_version TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    category TEXT NOT NULL,
    resolution INT NOT NULL
);

-- ============================================================
-- 2) 50.000 randomisierte Datensätze einfügen (Größere Laufzeitunterschiede)
-- ============================================================

INSERT INTO predictions_test (image_id, prediction, confidence, model_version, created_at, category, resolution)
SELECT
    'img_' || generate_series(1, 50000),
    (RANDOM() * 9)::INT,                        -- prediction 0–9
    RANDOM(),                                   -- confidence 0–1
    'v' || ((RANDOM() * 3)::INT + 1),           -- model_version v1–v4
    NOW() - (RANDOM() * INTERVAL '30 days'),    -- zufällige Zeitstempel
    (ARRAY['byHand','byComputer','fromInternet'])[ (RANDOM()*2)::INT + 1 ],
    (ARRAY[480,720,1080])[ (RANDOM()*2)::INT + 1 ]
;

-- ============================================================
-- 3) TEST 1 — Punktuelle Abfrage ohne Index
-- ============================================================
-- Erwarteter Output:
-- - Seq Scan
-- - viele Seiten gelesen (mehrere tausend)
-- - Laufzeit deutlich höher als mit Index

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;

-- ============================================================
-- 4) TEST 2 — B-Tree Index anlegen
-- ============================================================

CREATE INDEX idx_prediction_test ON predictions_test(prediction);

-- ============================================================
-- 5) TEST 3 — Punktuelle Abfrage mit Index
-- ============================================================
-- Erwarteter Output:
-- - Index Scan using idx_prediction_test
-- - deutlich weniger Seiten
-- - Laufzeit stark reduziert

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;

-- ============================================================
-- 6) TEST 4 — Bereichsabfrage (Selektivität)
-- ============================================================
-- Erwarteter Output:
-- - je nach Trefferanzahl:
--   * Index Scan (wenige Treffer)
--   * Bitmap Heap Scan + Bitmap Index Scan (mittlere Treffer)
--   * Seq Scan (viele Treffer)

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction BETWEEN 3 AND 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction BETWEEN 3 AND 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction BETWEEN 3 AND 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction BETWEEN 3 AND 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction BETWEEN 3 AND 7;

-- ============================================================
-- 7) TEST 5 — Zusammengesetzter Index
-- ============================================================

CREATE INDEX idx_pred_conf_test ON predictions_test(prediction, confidence);

-- Abfrage MIT führender Spalte
-- Erwarteter Output:
-- - Index Scan using idx_pred_conf_test

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7 AND confidence > 0.5;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7 AND confidence > 0.5;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7 AND confidence > 0.5;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7 AND confidence > 0.5;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7 AND confidence > 0.5;

-- Abfrage OHNE führende Spalte
-- Erwarteter Output:
-- - Seq Scan (Index wird ignoriert)

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.5;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.5;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.5;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.5;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.5;

-- ============================================================
-- 8) TEST 6 — Partieller Index
-- ============================================================

CREATE INDEX idx_partial_pred_test
ON predictions_test(prediction)
WHERE category = 'byHand';

-- Passende Abfrage
-- Erwarteter Output:
-- - Index Scan using idx_partial_pred_test

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byHand' AND prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byHand' AND prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byHand' AND prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byHand' AND prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byHand' AND prediction = 7;

-- Nicht passende Abfrage
-- Erwarteter Output:
-- - Seq Scan (Index wird ignoriert)

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byComputer' AND prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byComputer' AND prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byComputer' AND prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byComputer' AND prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE category = 'byComputer' AND prediction = 7;

-- ============================================================
-- 9) TEST 7 — Bitmap Scan
-- ============================================================

CREATE INDEX idx_confidence_test ON predictions_test(confidence);

-- Erwarteter Output:
-- - Bitmap Heap Scan
-- - Bitmap Index Scan

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.2 AND confidence < 0.8;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.2 AND confidence < 0.8;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.2 AND confidence < 0.8;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.2 AND confidence < 0.8;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE confidence > 0.2 AND confidence < 0.8;

-- ============================================================
-- 10) TEST 8 — EXPLAIN vs EXPLAIN ANALYZE
-- ============================================================
-- Erwarteter Output:
-- - EXPLAIN: nur geschätzte Kosten
-- - EXPLAIN ANALYZE: tatsächliche Laufzeit + tatsächliche Zeilen

EXPLAIN SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN SELECT * FROM predictions_test WHERE prediction = 7;

EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
EXPLAIN ANALYZE SELECT * FROM predictions_test WHERE prediction = 7;
