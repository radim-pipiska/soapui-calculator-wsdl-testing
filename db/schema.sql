
DROP TABLE IF EXISTS payments;
CREATE TABLE payments (
  id           INTEGER PRIMARY KEY,
  order_ref    TEXT    NOT NULL,   -- obchodní klíč
  amount_cents INTEGER NOT NULL,   -- 15000 = 150,00
  status       TEXT    NOT NULL
);

-- simulace: POST /payments -> 201, služba zapsala řádek
INSERT INTO payments (order_ref, amount_cents, status) VALUES ('ORD-1001', 15000, 'PENDING');
-- simulace: klient poslal stejný POST podruhé -> opět 201
INSERT INTO payments (order_ref, amount_cents, status) VALUES ('ORD-1001', 15000, 'PENDING');

---

SELECT COUNT(*) AS cnt FROM payments WHERE order_ref = 'ORD-1001';
