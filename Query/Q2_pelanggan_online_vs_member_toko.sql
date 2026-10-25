-- =====================================================================
-- Q2. Apakah pelanggan yang berbelanja secara online adalah orang yang
--     sama dengan pemegang kartu member di toko fisik?
--
-- Dasar  : dim_pelanggan adalah dimensi terpadu. Pelanggan web (S1) dan
--          member toko (S2) dicocokkan lewat nomor HP yang dinormalkan
--          (+62 / 62 / 8xxx -> 08xxx) di transformasi 09_dim_pelanggan.
--          Satu orang yang terdaftar di keduanya = satu id_pelanggan.
--          Pembeli marketplace (S3) hanya punya buyer.hash sehingga tidak
--          dapat dipadankan dan dilaporkan terpisah.
-- =====================================================================
USE nrg_dw;

-- (a) Irisan identitas: berapa pelanggan web yang juga member toko
SELECT SUM(is_pelanggan_web)                                         AS total_pelanggan_web,
       SUM(is_member_toko)                                           AS total_member_toko,
       SUM(is_pelanggan_web = 1 AND is_member_toko = 1)              AS web_dan_member,
       ROUND(100 * SUM(is_pelanggan_web = 1 AND is_member_toko = 1)
                 / SUM(is_pelanggan_web), 2)                         AS pct_pelanggan_web_yang_member,
       ROUND(100 * SUM(is_pelanggan_web = 1 AND is_member_toko = 1)
                 / SUM(is_member_toko), 2)                           AS pct_member_yang_belanja_web,
       SUM(is_pembeli_marketplace)                                   AS pembeli_marketplace_tidak_terpadankan
FROM dim_pelanggan
WHERE id_pelanggan > 0;

-- (b) Perilaku belanja: dari tiap jenis pelanggan, berapa yang benar-benar
--     bertransaksi di web, di toko, dan di keduanya, serta nilai belanjanya
WITH belanja AS (
    SELECT f.id_pelanggan,
           SUM(k.jenis_kanal = 'Situs Web')                                         AS baris_web,
           SUM(k.jenis_kanal = 'Toko Fisik')                                        AS baris_toko,
           SUM(CASE WHEN k.jenis_kanal = 'Situs Web'  THEN f.penjualan_netto END)   AS netto_web,
           SUM(CASE WHEN k.jenis_kanal = 'Toko Fisik' THEN f.penjualan_netto END)   AS netto_toko
    FROM fact_penjualan f
    JOIN dim_kanal k ON k.id_kanal = f.id_kanal
    WHERE f.id_pelanggan > 0
    GROUP BY f.id_pelanggan
)
SELECT p.jenis_pelanggan,
       COUNT(*)                                                      AS jumlah_pelanggan,
       SUM(COALESCE(b.baris_web, 0) > 0)                             AS pernah_belanja_web,
       SUM(COALESCE(b.baris_toko, 0) > 0)                            AS pernah_belanja_toko,
       SUM(COALESCE(b.baris_web, 0) > 0 AND COALESCE(b.baris_toko, 0) > 0) AS belanja_di_web_dan_toko,
       ROUND(SUM(COALESCE(b.netto_web, 0)), 0)                       AS penjualan_netto_web,
       ROUND(SUM(COALESCE(b.netto_toko, 0)), 0)                      AS penjualan_netto_toko
FROM dim_pelanggan p
LEFT JOIN belanja b ON b.id_pelanggan = p.id_pelanggan
WHERE p.id_pelanggan > 0
  AND p.is_pembeli_marketplace = 0
GROUP BY p.jenis_pelanggan
ORDER BY jumlah_pelanggan DESC;
