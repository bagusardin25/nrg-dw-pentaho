-- =====================================================================
-- Q3. Kampanye diskon mana yang berhasil menaikkan volume penjualan tanpa
--     menggerus margin?
--
-- Metode : pre-post comparison per kampanye pada kanal yang menjadi target
--          kampanye (berlaku_web / berlaku_toko / berlaku_marketplace).
--          - periode kampanye  = tanggal_mulai s.d. tanggal_selesai
--          - periode pembanding = jumlah hari yang sama tepat sebelum kampanye
--          Nilai dinormalkan per hari agar sebanding.
-- Kriteria BERHASIL:
--          qty per hari naik  DAN  margin kotor per hari tidak turun
--          (volume tambahan menutup potongan harga sehingga margin rupiah
--           tidak tergerus).
-- Catatan: periode kampanye dapat tumpang tindih; efeknya tidak dipisahkan.
--          Kampanye GAJIAN25 periode 28-06-2022 gagal validasi (target diskon
--          "sepuluh") sehingga tidak ada di dim_kampanye (lihat err_kampanye).
-- =====================================================================
USE nrg_dw;

WITH kampanye AS (
    SELECT id_kampanye, kode_promo, nama_kampanye, kanal_kampanye,
           berlaku_web, berlaku_toko, berlaku_marketplace,
           tanggal_mulai, tanggal_selesai, durasi_hari, target_diskon_persen,
           DATE_SUB(tanggal_mulai, INTERVAL durasi_hari DAY) AS pembanding_mulai,
           DATE_SUB(tanggal_mulai, INTERVAL 1 DAY)           AS pembanding_selesai
    FROM dim_kampanye
    WHERE id_kampanye > 0
),
penjualan AS (
    SELECT d.tanggal, k.jenis_kanal, f.qty, f.penjualan_netto, f.diskon_rp, f.margin_kotor
    FROM fact_penjualan f
    JOIN dim_tanggal d ON d.id_tanggal = f.id_tanggal
    JOIN dim_kanal   k ON k.id_kanal   = f.id_kanal
    WHERE f.margin_kotor IS NOT NULL
),
ringkas AS (
    SELECT c.id_kampanye,
           SUM(CASE WHEN p.tanggal >= c.tanggal_mulai THEN p.qty END)             AS qty_kampanye,
           SUM(CASE WHEN p.tanggal <  c.tanggal_mulai THEN p.qty END)             AS qty_pembanding,
           SUM(CASE WHEN p.tanggal >= c.tanggal_mulai THEN p.penjualan_netto END) AS netto_kampanye,
           SUM(CASE WHEN p.tanggal <  c.tanggal_mulai THEN p.penjualan_netto END) AS netto_pembanding,
           SUM(CASE WHEN p.tanggal >= c.tanggal_mulai THEN p.margin_kotor END)    AS margin_kampanye,
           SUM(CASE WHEN p.tanggal <  c.tanggal_mulai THEN p.margin_kotor END)    AS margin_pembanding,
           SUM(CASE WHEN p.tanggal >= c.tanggal_mulai THEN p.diskon_rp END)       AS diskon_kampanye
    FROM kampanye c
    JOIN penjualan p
      ON p.tanggal BETWEEN c.pembanding_mulai AND c.tanggal_selesai
     AND (   (c.berlaku_web = 1         AND p.jenis_kanal = 'Situs Web')
          OR (c.berlaku_toko = 1        AND p.jenis_kanal = 'Toko Fisik')
          OR (c.berlaku_marketplace = 1 AND p.jenis_kanal = 'Marketplace'))
    GROUP BY c.id_kampanye
),
hasil AS (
    SELECT c.kode_promo, c.nama_kampanye, c.kanal_kampanye, c.tanggal_mulai, c.tanggal_selesai,
           c.durasi_hari, c.target_diskon_persen,
           r.qty_pembanding  / c.durasi_hari                            AS qty_per_hari_sebelum,
           r.qty_kampanye    / c.durasi_hari                            AS qty_per_hari_kampanye,
           r.margin_pembanding / c.durasi_hari                          AS margin_per_hari_sebelum,
           r.margin_kampanye   / c.durasi_hari                          AS margin_per_hari_kampanye,
           100 * r.margin_pembanding / NULLIF(r.netto_pembanding, 0)    AS margin_pct_sebelum,
           100 * r.margin_kampanye   / NULLIF(r.netto_kampanye, 0)      AS margin_pct_kampanye,
           r.diskon_kampanye
    FROM kampanye c
    JOIN ringkas r ON r.id_kampanye = c.id_kampanye
)
SELECT kode_promo, nama_kampanye, kanal_kampanye, tanggal_mulai, tanggal_selesai, durasi_hari,
       target_diskon_persen,
       ROUND(qty_per_hari_sebelum, 2)                                            AS qty_per_hari_sebelum,
       ROUND(qty_per_hari_kampanye, 2)                                           AS qty_per_hari_kampanye,
       ROUND(100 * (qty_per_hari_kampanye - qty_per_hari_sebelum) / qty_per_hari_sebelum, 2) AS perubahan_volume_pct,
       ROUND(margin_per_hari_sebelum, 0)                                         AS margin_per_hari_sebelum,
       ROUND(margin_per_hari_kampanye, 0)                                        AS margin_per_hari_kampanye,
       ROUND(100 * (margin_per_hari_kampanye - margin_per_hari_sebelum) / margin_per_hari_sebelum, 2) AS perubahan_margin_pct,
       ROUND(margin_pct_sebelum, 2)                                              AS margin_pct_sebelum,
       ROUND(margin_pct_kampanye, 2)                                             AS margin_pct_kampanye,
       CASE
           WHEN qty_per_hari_kampanye > qty_per_hari_sebelum
            AND margin_per_hari_kampanye >= margin_per_hari_sebelum THEN 'BERHASIL: volume naik, margin terjaga'
           WHEN qty_per_hari_kampanye > qty_per_hari_sebelum      THEN 'Volume naik, margin tergerus'
           ELSE 'Tidak menaikkan volume'
       END                                                                       AS kesimpulan
FROM hasil
ORDER BY (qty_per_hari_kampanye > qty_per_hari_sebelum
          AND margin_per_hari_kampanye >= margin_per_hari_sebelum) DESC,
         perubahan_volume_pct DESC;
