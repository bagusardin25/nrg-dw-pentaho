-- =====================================================================
-- Q1. Berapa margin kotor per sub-kategori produk per kanal, dibandingkan
--     dengan kuartal yang sama pada tahun lalu?
--
-- Sumber : fact_penjualan x dim_produk x dim_kanal x dim_tanggal
-- Catatan: - margin_kotor = penjualan_netto - hpp - fee_komisi - fee_layanan
--            (semua tanpa PPN; fee hanya kanal marketplace)
--          - baris dengan HPP belum tersedia (inferred member / late
--            arriving, mis. ORD-9999) dikecualikan dari perhitungan margin
--          - data tersedia 2022-Q1 s.d. 2023-Q1, sehingga pembanding YoY
--            yang lengkap adalah 2023-Q1 vs 2022-Q1
-- =====================================================================
USE nrg_dw;

WITH margin_kuartal AS (
    SELECT p.kategori,
           p.sub_kategori,
           k.jenis_kanal,
           d.tahun,
           d.kuartal,
           SUM(f.qty)             AS qty,
           SUM(f.penjualan_netto) AS penjualan_netto,
           SUM(f.margin_kotor)    AS margin_kotor
    FROM fact_penjualan f
    JOIN dim_produk  p ON p.produk_key  = f.produk_key
    JOIN dim_kanal   k ON k.kanal_key   = f.kanal_key
    JOIN dim_tanggal d ON d.tanggal_key = f.tanggal_key
    WHERE f.margin_kotor IS NOT NULL
    GROUP BY p.kategori, p.sub_kategori, k.jenis_kanal, d.tahun, d.kuartal
)
SELECT kini.kategori,
       kini.sub_kategori,
       kini.jenis_kanal,
       CONCAT(kini.tahun, '-Q', kini.kuartal)                          AS periode,
       ROUND(kini.margin_kotor, 0)                                     AS margin_kotor,
       ROUND(100 * kini.margin_kotor / kini.penjualan_netto, 2)        AS margin_pct,
       CONCAT(lalu.tahun, '-Q', lalu.kuartal)                          AS periode_tahun_lalu,
       ROUND(lalu.margin_kotor, 0)                                     AS margin_kotor_tahun_lalu,
       ROUND(100 * lalu.margin_kotor / lalu.penjualan_netto, 2)        AS margin_pct_tahun_lalu,
       ROUND(kini.margin_kotor - lalu.margin_kotor, 0)                 AS selisih_margin,
       ROUND(100 * (kini.margin_kotor - lalu.margin_kotor)
                 / NULLIF(ABS(lalu.margin_kotor), 0), 2)               AS pertumbuhan_yoy_pct
FROM margin_kuartal kini
LEFT JOIN margin_kuartal lalu
       ON  lalu.sub_kategori = kini.sub_kategori
       AND lalu.jenis_kanal  = kini.jenis_kanal
       AND lalu.kuartal      = kini.kuartal
       AND lalu.tahun        = kini.tahun - 1
WHERE kini.tahun = 2023 AND kini.kuartal = 1      -- kuartal yang dianalisis (ubah sesuai kebutuhan)
ORDER BY kini.kategori, kini.sub_kategori, kini.jenis_kanal;
