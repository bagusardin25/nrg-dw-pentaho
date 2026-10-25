# Data Warehouse NRG (Nusantara Retail Group) – Tugas Kelompok 1

**Kelompok 7** · Repositori: https://github.com/bagusardin25/nrg-dw-pentaho

| Nama | NIM |
|---|---|
| Aldi Rachmatdianto | 102062400069 |
| Bagus Ardin Prayoga | 102062400064 |
| Naufal Syahruradli | 102062400103 |
| Ida Bagus Giri Krisnabhawa | 102062400117 |

Star schema berbasis satu tabel fakta (`fact_penjualan`) yang mengintegrasikan lima sistem sumber (S1–S5)
menggunakan **Pentaho Data Integration 9.3** dan **MySQL 8.4 (Laragon)**.

## Struktur folder

| Folder / berkas | Isi |
|---|---|
| `Dokumen_Desain/star_schema_nrg_dw.png` | Diagram star schema |
| `DDL/nrg_dw_ddl.sql` | DDL data warehouse `nrg_dw` (dijalankan otomatis oleh job) |
| `ETL_Pentaho/00_job_nrg_dw.kjb` | Job utama (DDL → 12 transformation) |
| `ETL_Pentaho/01..12_*.ktr` | Transformation Pentaho |
| `Query/Q1..Q4_*.sql` | Empat kueri pembuktian |
| `Data_Sumber/` | Paket data sumber (tidak diubah) |

Dokumen desain dimensional / laporan (.docx dan .pdf) tidak disimpan di repositori ini; dokumen tersebut
dikumpulkan bersama arsip pengumpulan di LMS.

## Koneksi database (sudah tertanam di setiap .ktr/.kjb)

| Nama koneksi | Tipe | Host:port | Database | User |
|---|---|---|---|---|
| `conn_nrg_ecom` | MySQL | localhost:3306 | `nrg_ecom` (S1) | root (tanpa password) |
| `conn_nrg_dw` | MySQL | localhost:3306 | `nrg_dw` (target, dibuat otomatis bila belum ada) | root (tanpa password) |

Jika password MySQL berbeda, ubah di Spoon: *View → Database connections* pada job/transformation.

## Cara menjalankan dari kondisi kosong

1. Nyalakan MySQL di Laragon.
2. Muat S1 ke MySQL (sekali saja): impor `Data_Sumber/S1_ecom_db_schema_mysql.sql`, lalu dari folder `Data_Sumber` jalankan:
   ```bash
   python load_all.py
   ```
3. Jalankan job utama:
   - **Spoon**: buka `Spoon-Java11.bat` → *File → Open* → `ETL_Pentaho/00_job_nrg_dw.kjb` → *Run*.
   - **Command line** (dari folder `D:\Pentaho\data-integration`, dengan Java 11):
     ```bat
     Kitchen.bat /file:"D:\Project\NRG_DW\ETL_Pentaho\00_job_nrg_dw.kjb" /level:Basic
     ```
4. Jalankan kueri `Query/Q1..Q4` pada database `nrg_dw`.

Job menjalankan DDL (drop & create seluruh tabel `nrg_dw` + anggota default dimensi), lalu transformation
berurutan (± 2 menit):

| # | Transformation | Hasil |
|---|---|---|
| 1 | `01_ref_kota` | `ref_kota` (alias kota → kota baku) |
| 2 | `02_dim_tanggal` | `dim_tanggal` 2021–2024 |
| 3 | `03_dim_pemasok` | `dim_pemasok` (S4) |
| 4 | `04_dim_produk` | `dim_produk` SCD tipe 2 (riwayat harga pokok S4) |
| 5 | `05_stg_mpl` | `stg_mpl_item` (JSON S3 diratakan, dedup, alokasi fee) + `stg_mpl_duplikat` |
| 6 | `06_map_produk` | `map_produk` (S1/S2/S3 → material_no) + inferred member untuk produk late arriving |
| 7 | `07_dim_kanal` | `dim_kanal` (web, 2 marketplace, 42 toko) |
| 8 | `08_dim_kampanye` | `dim_kampanye` (S5 dibersihkan) + `err_kampanye` (baris gagal validasi) |
| 9 | `09_dim_pelanggan` | `dim_pelanggan` terpadu (web + member via nomor HP, pembeli marketplace) |
| 10 | `10_fact_penjualan_web` | fakta S1 |
| 11 | `11_fact_penjualan_toko` | fakta S2 |
| 12 | `12_fact_penjualan_marketplace` | fakta S3 |

Path berkas sumber di dalam transformation memakai `${Internal.Entry.Current.Directory}/../Data_Sumber`,
jadi struktur folder ini harus dipertahankan. Transformation 03–12 bergantung pada hasil transformation
sebelumnya; jalankan lewat job agar urutan dan DDL terjamin.

## Hasil load (verifikasi)

| Tabel | Baris |
|---|---|
| `fact_penjualan` | 14.419 (S1 4.236 · S2 8.386 · S3 1.797) |
| `dim_pelanggan` | 1.558 (200 orang terdaftar sebagai pelanggan web **dan** member toko) |
| `dim_produk` | 81 (79 versi ERP + 1 inferred + 1 default) |
| `dim_kanal` / `dim_kampanye` / `dim_pemasok` / `dim_tanggal` | 46 / 17 / 11 / 1.461 |
| `err_kampanye` / `stg_mpl_duplikat` | 1 / 34 |

Penjualan netto per sumber direkonsiliasi ulang langsung dari berkas sumber dan hasilnya sama persis.

```sql
SELECT sumber_sistem, COUNT(*) baris, SUM(penjualan_netto) netto, SUM(margin_kotor) margin
FROM nrg_dw.fact_penjualan GROUP BY sumber_sistem;
```
