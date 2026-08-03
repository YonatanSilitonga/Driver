# Driver Mobile Application

## UI Requirement - Phase 1 (Home Page)

# Gambaran Umum

Aplikasi Driver merupakan aplikasi mobile yang digunakan oleh driver
operasional PT Sentral Logistik Bersama (SLB) untuk membantu menjalankan
aktivitas pengambilan barang dari Seller menuju Gudang Outgoing.

Pada tahap pertama pengembangan (Phase 1), aplikasi akan memiliki **5
menu utama** pada Bottom Navigation, yaitu:

1.  Beranda
2.  Tugas
3.  Riwayat
4.  Laporan
5.  Profil

Namun, **halaman yang akan dirancang dan dikembangkan pada tahap ini
hanya halaman Beranda (Home)**.

Halaman lainnya hanya perlu ditampilkan sebagai menu pada Bottom
Navigation tanpa isi atau fungsionalitas terlebih dahulu.

------------------------------------------------------------------------

# Struktur Bottom Navigation

  Menu      Status
  --------- ---------------------
  Beranda   Dibuat pada Phase 1
  Tugas     Placeholder
  Riwayat   Placeholder
  Laporan   Placeholder
  Profil    Placeholder

------------------------------------------------------------------------

# Halaman Beranda (Home)

## Tujuan

Halaman Beranda merupakan halaman utama yang ditampilkan setelah driver
berhasil login.

Halaman ini digunakan untuk memberikan informasi mengenai kendaraan yang
digunakan, ringkasan pekerjaan hari ini, serta penugasan aktif yang
harus segera dijalankan.

## Struktur Halaman

1.  Status Kendaraan
2.  Status Rute
3.  Penugasan Aktif

### Status Kendaraan

Informasi: - Nama Kendaraan - Model Kendaraan - Nomor Plat - Kapasitas
KOLI - Kapasitas Berat (Kg)

### Status Rute

Informasi: - Jumlah Rute Ditugaskan - Jumlah Rute Selesai - Total AWB -
Total KOLI

### Penugasan Aktif

Informasi: - Seller Tujuan - Alamat Seller - Estimasi Total AWB -
Estimasi Total KOLI

Aksi: - Mulai Perjalanan

## Catatan

-   Menampilkan penugasan aktif milik driver yang login.
-   Jika belum ada penugasan, tampilkan informasi bahwa belum ada tugas.
-   Bottom Navigation tetap memiliki 5 menu, namun hanya Beranda yang
    memiliki isi pada Phase 1.

## Scope Phase 1

Dikerjakan: - Bottom Navigation (5 Menu) - Halaman Beranda

Belum dikerjakan: - Tugas - Riwayat - Laporan - Profil
