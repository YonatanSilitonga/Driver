# Changelog Mobile App - Tower Control

Semua perubahan dan catatan rilis aplikasi mobile driver Tower Control dicatat dalam berkas ini.

---

## [1.2.1] - 2026-09-07

### 🔄 Perubahan Nama Istilah Bongkar & Muat
- Membedakan istilah operasional stop secara jelas dan konsisten di seluruh layar antarmuka driver:
  - **Gateway / DC**: Menampilkan istilah **"Bongkar"** / **"Bongkar Barang"** (dengan ikon bongkar / transit).
  - **Seller / Pick-up**: Menampilkan istilah **"Muat"** / **"Muat Barang"** (dengan ikon muat barang).
- Penyesuaian label timeline stop, indikator badge, tombol aksi tahap perjalanan, dan dialog konfirmasi muat/bongkar.

### 🎨 Peningkatan Layout & Kolom Login
- Desain ulang tampilan kolom input login agar lebih ergonomis, modern, dan nyaman di berbagai ukuran layar HP.
- Dukungan interaktif:
  - Toggle visibilitas password (show/hide password).
  - Pengaturan keyboard behavior dan auto-scroll yang mulus agar kolom input tidak tertutup keyboard saat mengetik.
  - Spacing dan responsivitas layout saat keyboard aktif.
  - Penyesuaian badge indikator versi aplikasi di bagian bawah halaman login.

### 🚗 Alur Ritase Pengembalian Mobil ke Gudang
- Penambahan pemberhentian (stop) terakhir untuk pengembalian unit armada ke Gudang Outgoing / transit:
  - Timeline stop menampilkan destinasi akhir pengembalian mobil dengan ikon gudang armada.
  - Saat driver tiba di gudang pengembalian, status secara otomatis tercatat **"Tiba"** (bukan "Muat Barang").
  - Form input koli/AWB/manifest disembunyikan secara cerdas karena pengembalian mobil tidak memerlukan input muatan.
  - Kartu ringkasan pengembalian mobil (**Gudang Return Card**) ditampilkan dengan instruksi parkir dan pengembalian unit.
  - Tombol aksi kontekstual: **"Selesaikan Ritase & Parkir Mobil"** untuk mengakhiri ritase secara utuh.

### 🔘 Tombol "Mulai Perjalanan"
- Perbaikan konsistensi teks tombol aksi utama rute: tombol aksi awal di halaman utama dipastikan paten menampilkan **"Mulai Perjalanan"** (menggantikan "Lanjutkan Perjalanan" yang sebelumnya ambigu bagi driver saat memulai rute baru).

---

## [1.1.0] - 2026-08-28
- Dukungan shift lintas hari (*overnight*).
- Toleransi rute 2 jam lebih awal untuk persiapan armada.
- Fitur *keep awake* / penguncian layar rute aktif selama perjalanan.
- Perbaikan sinkronisasi nama gudang & gateway pada riwayat perjalanan driver.

---

## [1.0.3] - 2026-08-18
- Pelacakan koordinat real-time latar belakang (*background GPS tracking*).
- Form input manifest & bukti foto serah terima barang di seller.
- Sistem auto-update aplikasi langsung dari server Tower Control.
