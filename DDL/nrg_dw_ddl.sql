-- =====================================================================
-- DDL DATA WAREHOUSE NRG (Nusantara Retail Group)
-- Database : nrg_dw (MySQL 8.x)
-- Skema    : star schema, 1 tabel fakta (fact_penjualan) + 6 dimensi
--            + tabel pendukung ETL (referensi, pemetaan, staging, error)
-- Dijalankan otomatis oleh job 00_job_nrg_dw.kjb (entry "DDL nrg_dw"),
-- sehingga setiap eksekusi job dimulai dari kondisi kosong.
-- =====================================================================

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS fact_penjualan;
DROP TABLE IF EXISTS dim_tanggal;
DROP TABLE IF EXISTS dim_produk;
DROP TABLE IF EXISTS dim_pemasok;
DROP TABLE IF EXISTS dim_kanal;
DROP TABLE IF EXISTS dim_pelanggan;
DROP TABLE IF EXISTS dim_kampanye;
DROP TABLE IF EXISTS map_produk;
DROP TABLE IF EXISTS ref_kota;
DROP TABLE IF EXISTS stg_mpl_item;
DROP TABLE IF EXISTS stg_mpl_duplikat;
DROP TABLE IF EXISTS err_kampanye;

SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- TABEL PENDUKUNG ETL
-- ---------------------------------------------------------------------

-- Referensi alias kota (ref_kota.csv) -> nama kota baku
CREATE TABLE ref_kota (
  alias_kota      VARCHAR(60)  NOT NULL,
  kota_baku       VARCHAR(60)  NOT NULL,
  PRIMARY KEY (alias_kota)
) ENGINE = InnoDB;

-- Tabel pemetaan produk: kode produk tiap kanal -> material_no (S4)
CREATE TABLE map_produk (
  sumber              VARCHAR(5)   NOT NULL,
  kode_produk_sumber  VARCHAR(40)  NOT NULL,
  nama_produk_sumber  VARCHAR(200),
  material_no         VARCHAR(40)  NOT NULL,
  status_pemetaan     VARCHAR(30)  NOT NULL,
  metode_pemetaan     VARCHAR(100),
  PRIMARY KEY (sumber, kode_produk_sumber)
) ENGINE = InnoDB;

-- Staging S3 (marketplace): item invoice yang sudah diratakan,
-- dideduplikasi, dan fee-nya sudah dialokasikan per baris item
CREATE TABLE stg_mpl_item (
  invoice              VARCHAR(40)  NOT NULL,
  seller_sku           VARCHAR(40)  NOT NULL,
  channel              VARCHAR(30),
  buyer_hash           VARCHAR(40),
  buyer_city           VARCHAR(60),
  paid_at_utc          DATETIME,
  waktu_wib            DATETIME,
  diambil_pada         DATETIME,
  qty                  INT,
  price_incl_ppn       DECIMAL(15,2),
  voucher_incl_ppn     DECIMAL(15,2),
  nilai_baris_incl     DECIMAL(15,2),
  nilai_invoice_incl   DECIMAL(15,2),
  porsi_alokasi        DECIMAL(12,8),
  fee_commission_inv   DECIMAL(15,2),
  fee_service_inv      DECIMAL(15,2),
  fee_commission_alok  DECIMAL(15,2),
  fee_service_alok     DECIMAL(15,2),
  sumber_file          VARCHAR(255),
  PRIMARY KEY (invoice, seller_sku)
) ENGINE = InnoDB;

-- Jejak baris duplikat S3 (hasil retry API) yang dibuang saat deduplikasi
CREATE TABLE stg_mpl_duplikat (
  id                   INT NOT NULL AUTO_INCREMENT,
  invoice              VARCHAR(40),
  seller_sku           VARCHAR(40),
  diambil_pada         DATETIME,
  sumber_file          VARCHAR(255),
  keterangan           VARCHAR(255),
  waktu_load           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE = InnoDB;

-- Baris S5 yang gagal validasi (mis. target_diskon_persen = 'sepuluh')
CREATE TABLE err_kampanye (
  id                    INT NOT NULL AUTO_INCREMENT,
  kode_promo            VARCHAR(50),
  nama_kampanye         VARCHAR(150),
  jenis_promo           VARCHAR(50),
  kanal                 VARCHAR(50),
  tgl_mulai             VARCHAR(20),
  tgl_selesai           VARCHAR(20),
  target_diskon_persen  VARCHAR(50),
  pic                   VARCHAR(100),
  jumlah_error          INT,
  deskripsi_error       VARCHAR(1000),
  kolom_error           VARCHAR(200),
  kode_error            VARCHAR(50),
  waktu_load            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- DIMENSI
-- ---------------------------------------------------------------------

CREATE TABLE dim_tanggal (
  id_tanggal        INT          NOT NULL,          -- yyyymmdd
  tanggal            DATE         NOT NULL,
  hari_dalam_bulan   TINYINT,
  hari_dalam_minggu  TINYINT,                        -- 1 = Senin ... 7 = Minggu
  nama_hari          VARCHAR(10),
  is_akhir_pekan     TINYINT,
  minggu_dalam_tahun TINYINT,
  bulan              TINYINT,
  nama_bulan         VARCHAR(12),
  kuartal            TINYINT,
  nama_kuartal       VARCHAR(2),
  tahun              SMALLINT,
  tahun_bulan        VARCHAR(7),                     -- 2022-01
  tahun_kuartal      VARCHAR(7),                     -- 2022-Q1
  PRIMARY KEY (id_tanggal),
  UNIQUE KEY uk_tanggal (tanggal)
) ENGINE = InnoDB;

CREATE TABLE dim_kanal (
  id_kanal      INT          NOT NULL AUTO_INCREMENT,
  kanal_kode     VARCHAR(30)  NOT NULL,              -- WEB / TSxx / marketplace_a / marketplace_b
  jenis_kanal    VARCHAR(20)  NOT NULL,              -- Situs Web / Toko Fisik / Marketplace
  platform       VARCHAR(50),
  kode_toko      VARCHAR(10),
  nama_toko      VARCHAR(100),
  format_toko    VARCHAR(30),
  kota           VARCHAR(60),
  provinsi       VARCHAR(60),
  tanggal_buka   DATE,
  PRIMARY KEY (id_kanal),
  UNIQUE KEY uk_kanal_kode (kanal_kode)
) ENGINE = InnoDB;

CREATE TABLE dim_pemasok (
  id_pemasok    INT          NOT NULL AUTO_INCREMENT,
  kode_pemasok   VARCHAR(20)  NOT NULL,
  nama_pemasok   VARCHAR(150) NOT NULL,
  kota           VARCHAR(60),
  kontak         VARCHAR(30),
  PRIMARY KEY (id_pemasok),
  UNIQUE KEY uk_kode_pemasok (kode_pemasok)
) ENGINE = InnoDB;

-- SCD Tipe 2: satu baris per versi harga pokok (berlaku_sejak s.d. berlaku_sampai)
CREATE TABLE dim_produk (
  id_produk      INT           NOT NULL AUTO_INCREMENT,
  material_no     VARCHAR(40)   NOT NULL,
  nama_produk     VARCHAR(200),
  merk            VARCHAR(60),
  kategori        VARCHAR(60),
  sub_kategori    VARCHAR(60),
  harga_pokok     DECIMAL(15,2),                     -- NULL untuk inferred member
  status_produk   VARCHAR(20),
  id_pemasok     INT,
  nama_pemasok    VARCHAR(150),
  versi           INT,
  berlaku_sejak   DATE          NOT NULL,
  berlaku_sampai  DATE          NOT NULL,
  is_current      TINYINT       NOT NULL DEFAULT 1,
  is_inferred     TINYINT       NOT NULL DEFAULT 0,  -- 1 = late arriving dimension
  sumber_data     VARCHAR(30),
  PRIMARY KEY (id_produk),
  UNIQUE KEY uk_material_versi (material_no, berlaku_sejak),
  KEY idx_material_periode (material_no, berlaku_sejak, berlaku_sampai)
) ENGINE = InnoDB;

-- Pelanggan terpadu: pelanggan web (S1) dan member toko (S2) digabung
-- berdasarkan nomor HP yang dinormalkan; pembeli marketplace (S3) per buyer.hash
CREATE TABLE dim_pelanggan (
  id_pelanggan          INT          NOT NULL AUTO_INCREMENT,
  pelanggan_nk           VARCHAR(60)  NOT NULL,      -- HP:08xxxx / MPL:<hash> / default
  jenis_pelanggan        VARCHAR(40),
  nama                   VARCHAR(150),
  no_hp_norm             VARCHAR(20),
  email                  VARCHAR(150),
  gender                 CHAR(1),
  kota                   VARCHAR(60),
  id_pelanggan_web       INT,
  no_member_toko         VARCHAR(20),
  buyer_hash_mpl         VARCHAR(40),
  is_pelanggan_web       TINYINT      NOT NULL DEFAULT 0,
  is_member_toko         TINYINT      NOT NULL DEFAULT 0,
  is_pembeli_marketplace TINYINT      NOT NULL DEFAULT 0,
  tgl_registrasi_web     DATE,
  tgl_join_member        DATE,
  PRIMARY KEY (id_pelanggan),
  UNIQUE KEY uk_pelanggan_nk (pelanggan_nk),
  UNIQUE KEY uk_hp (no_hp_norm),
  KEY idx_id_web (id_pelanggan_web),
  KEY idx_member (no_member_toko),
  KEY idx_buyer (buyer_hash_mpl)
) ENGINE = InnoDB;

CREATE TABLE dim_kampanye (
  id_kampanye          INT          NOT NULL AUTO_INCREMENT,
  kode_promo            VARCHAR(50)  NOT NULL,
  nama_kampanye         VARCHAR(150),
  jenis_promo           VARCHAR(50),
  kanal_kampanye        VARCHAR(50),
  berlaku_web           TINYINT      NOT NULL DEFAULT 0,
  berlaku_toko          TINYINT      NOT NULL DEFAULT 0,
  berlaku_marketplace   TINYINT      NOT NULL DEFAULT 0,
  tanggal_mulai         DATE,
  tanggal_selesai       DATE,
  durasi_hari           INT,
  target_diskon_persen  DECIMAL(5,2),
  pic                   VARCHAR(100),
  PRIMARY KEY (id_kampanye),
  UNIQUE KEY uk_kampanye (kode_promo, tanggal_mulai)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- FAKTA  (grain: satu baris per item transaksi)
--   S1 = order line, S2 = trx line, S3 = invoice item
--   Semua nilai rupiah TANPA PPN, semua waktu dalam WIB
-- ---------------------------------------------------------------------
CREATE TABLE fact_penjualan (
  id_penjualan               BIGINT        NOT NULL AUTO_INCREMENT,
  id_tanggal            INT           NOT NULL,
  id_produk             INT           NOT NULL,
  id_pemasok            INT           NOT NULL,
  id_kanal              INT           NOT NULL,
  id_pelanggan          INT           NOT NULL,
  id_kampanye           INT           NOT NULL,
  -- degenerate dimension / atribut lineage
  sumber_sistem          VARCHAR(5)    NOT NULL,     -- S1 / S2 / S3
  nomor_transaksi        VARCHAR(50)   NOT NULL,     -- order_id / trx_no / invoice
  line_id                VARCHAR(50)   NOT NULL,     -- order_item_id / line_seq / seller_sku
  kode_produk_sumber     VARCHAR(40),
  waktu_transaksi_wib    DATETIME,
  metode_pembayaran      VARCHAR(60),
  -- measure
  qty                    INT           NOT NULL,
  harga_satuan_excl_ppn  DECIMAL(15,2),
  penjualan_bruto        DECIMAL(15,2),              -- qty x harga satuan (tanpa PPN)
  diskon_rp              DECIMAL(15,2),              -- diskon/voucher (tanpa PPN)
  penjualan_netto        DECIMAL(15,2),              -- bruto - diskon
  hpp_satuan             DECIMAL(15,2),
  hpp                    DECIMAL(15,2),              -- qty x harga_pokok versi berlaku
  fee_komisi             DECIMAL(15,2),              -- alokasi fee commission (S3)
  fee_layanan            DECIMAL(15,2),              -- alokasi fee service (S3)
  margin_kotor           DECIMAL(15,2),              -- netto - hpp - fee_komisi - fee_layanan
  qty_retur              INT,
  nilai_retur            DECIMAL(15,2),
  PRIMARY KEY (id_penjualan),
  UNIQUE KEY uk_fact_line (sumber_sistem, nomor_transaksi, line_id),
  KEY idx_fact_tanggal (id_tanggal),
  KEY idx_fact_produk (id_produk),
  KEY idx_fact_kanal (id_kanal),
  KEY idx_fact_pelanggan (id_pelanggan),
  KEY idx_fact_kampanye (id_kampanye),
  CONSTRAINT fk_fact_tanggal   FOREIGN KEY (id_tanggal)   REFERENCES dim_tanggal (id_tanggal),
  CONSTRAINT fk_fact_produk    FOREIGN KEY (id_produk)    REFERENCES dim_produk (id_produk),
  CONSTRAINT fk_fact_pemasok   FOREIGN KEY (id_pemasok)   REFERENCES dim_pemasok (id_pemasok),
  CONSTRAINT fk_fact_kanal     FOREIGN KEY (id_kanal)     REFERENCES dim_kanal (id_kanal),
  CONSTRAINT fk_fact_pelanggan FOREIGN KEY (id_pelanggan) REFERENCES dim_pelanggan (id_pelanggan),
  CONSTRAINT fk_fact_kampanye  FOREIGN KEY (id_kampanye)  REFERENCES dim_kampanye (id_kampanye)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- ANGGOTA DEFAULT DIMENSI (surrogate key negatif)
--   -1 = tidak dikenal / tidak terpetakan
--   -2 = bukan member / tanpa kampanye
-- ---------------------------------------------------------------------
INSERT INTO dim_produk (id_produk, material_no, nama_produk, merk, kategori, sub_kategori,
                        harga_pokok, status_produk, id_pemasok, nama_pemasok, versi,
                        berlaku_sejak, berlaku_sampai, is_current, is_inferred, sumber_data)
VALUES (-1, 'N/A', 'Produk Tidak Dikenal', 'N/A', 'N/A', 'N/A',
        NULL, 'N/A', -1, 'N/A', 0, '1900-01-01', '9999-12-31', 1, 0, 'DEFAULT');

INSERT INTO dim_pemasok (id_pemasok, kode_pemasok, nama_pemasok, kota, kontak)
VALUES (-1, 'N/A', 'Pemasok Tidak Dikenal', 'N/A', NULL);

INSERT INTO dim_kanal (id_kanal, kanal_kode, jenis_kanal, platform, kota)
VALUES (-1, 'N/A', 'Tidak Dikenal', 'N/A', 'N/A');

INSERT INTO dim_pelanggan (id_pelanggan, pelanggan_nk, jenis_pelanggan, nama)
VALUES (-1, 'N/A', 'Tidak Dikenal', 'Pelanggan Tidak Dikenal'),
       (-2, 'NON-MEMBER', 'Non-Member Toko', 'Pembeli Toko Non-Member');

INSERT INTO dim_kampanye (id_kampanye, kode_promo, nama_kampanye, jenis_promo, kanal_kampanye)
VALUES (-1, 'TIDAK TERIDENTIFIKASI', 'Diskon di luar kampanye valid / kampanye gagal validasi', 'N/A', 'N/A'),
       (-2, 'TANPA KAMPANYE', 'Tanpa Kampanye / Tanpa Diskon', 'N/A', 'N/A');
