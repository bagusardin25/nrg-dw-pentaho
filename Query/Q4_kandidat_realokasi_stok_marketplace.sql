-- =====================================================================
-- Q4. Produk apa saja yang volume penjualannya tinggi di marketplace tetapi
--     rendah di toko fisik dan web, sehingga menjadi kandidat pemindahan
--     alokasi stok ke marketplace?
--
-- Metode : volume (qty) per material_no per kanal. Karena ukuran kanal
--          berbeda jauh, dipakai PANGSA: qty produk / total qty kanal.
--          indeks_marketplace = pangsa di marketplace / pangsa di toko+web
--          ( > 1 berarti produk relatif lebih laku di marketplace ).
-- Kriteria KANDIDAT:
--          - volume marketplace tinggi : peringkat persentil qty marketplace >= 0,75
--            (25% teratas)
--          - volume toko + web rendah  : peringkat persentil qty toko+web <= 0,50
--            (50% terbawah)
-- Produk inferred (belum ada di ERP) dikecualikan.
-- =====================================================================
USE nrg_dw;

WITH volume AS (
    SELECT p.material_no, p.nama_produk, p.kategori, p.sub_kategori,
           SUM(CASE WHEN k.jenis_kanal = 'Marketplace' THEN f.qty ELSE 0 END) AS qty_marketplace,
           SUM(CASE WHEN k.jenis_kanal = 'Toko Fisik'  THEN f.qty ELSE 0 END) AS qty_toko,
           SUM(CASE WHEN k.jenis_kanal = 'Situs Web'   THEN f.qty ELSE 0 END) AS qty_web
    FROM fact_penjualan f
    JOIN dim_produk p ON p.id_produk = f.id_produk
    JOIN dim_kanal  k ON k.id_kanal  = f.id_kanal
    WHERE p.is_inferred = 0 AND p.id_produk > 0
    GROUP BY p.material_no, p.nama_produk, p.kategori, p.sub_kategori
),
pangsa AS (
    SELECT v.*,
           v.qty_toko + v.qty_web                                                  AS qty_toko_web,
           v.qty_marketplace / SUM(v.qty_marketplace) OVER ()                      AS pangsa_marketplace,
           (v.qty_toko + v.qty_web) / SUM(v.qty_toko + v.qty_web) OVER ()          AS pangsa_toko_web,
           PERCENT_RANK() OVER (ORDER BY v.qty_marketplace)                        AS prank_marketplace,
           PERCENT_RANK() OVER (ORDER BY v.qty_toko + v.qty_web)                   AS prank_toko_web
    FROM volume v
)
SELECT material_no, nama_produk, sub_kategori,
       qty_marketplace, qty_toko, qty_web,
       ROUND(100 * pangsa_marketplace, 2)                AS pangsa_marketplace_pct,
       ROUND(100 * pangsa_toko_web, 2)                   AS pangsa_toko_web_pct,
       ROUND(pangsa_marketplace / pangsa_toko_web, 2)    AS indeks_marketplace,
       ROUND(prank_marketplace, 2)                       AS persentil_marketplace,
       ROUND(prank_toko_web, 2)                          AS persentil_toko_web
FROM pangsa
WHERE prank_marketplace >= 0.75
  AND prank_toko_web    <= 0.50
ORDER BY indeks_marketplace DESC;
