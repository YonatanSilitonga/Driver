BEGIN;
DELETE FROM ritase WHERE tanggal = CURRENT_DATE;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D3-R1', CURRENT_DATE, 3, 2, 2, 1, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 1, 'gudang 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_seller, keterangan)
    VALUES (new_ritase_id, 2, 'seller', 3, 'seller 3');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_seller, keterangan)
    VALUES (new_ritase_id, 3, 'seller', 1, 'seller 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 4, 'drop_point', 2, 'drop_point 2');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D3-R2', CURRENT_DATE, 3, 2, 2, 2, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 1, 'gudang 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_seller, keterangan)
    VALUES (new_ritase_id, 2, 'seller', 3, 'seller 3');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 3, 'gudang', 1, 'gudang 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 4, 'drop_point', 2, 'drop_point 2');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D2-R1', CURRENT_DATE, 2, 6, 2, 1, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 1, 'gudang 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_seller, keterangan)
    VALUES (new_ritase_id, 2, 'seller', 2, 'seller 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 3, 'gudang', 2, 'gudang 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 4, 'drop_point', 2, 'drop_point 2');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D2-R2', CURRENT_DATE, 2, 6, 2, 2, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 1, 'drop_point', 2, 'drop_point 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_seller, keterangan)
    VALUES (new_ritase_id, 2, 'seller', 2, 'seller 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 3, 'gudang', 2, 'gudang 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 4, 'drop_point', 2, 'drop_point 2');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D1-R2', CURRENT_DATE, 1, 11, 2, 2, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 1, 'drop_point', 2, 'drop_point 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_seller, keterangan)
    VALUES (new_ritase_id, 2, 'seller', 4, 'seller 4');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_seller, keterangan)
    VALUES (new_ritase_id, 3, 'seller', 1, 'seller 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 4, 'gudang', 1, 'gudang 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 5, 'drop_point', 2, 'drop_point 2');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D4-R2', CURRENT_DATE, 4, 15, 2, 2, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 1, 'gudang 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_seller, keterangan)
    VALUES (new_ritase_id, 2, 'seller', 7, 'seller 7');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 3, 'drop_point', 2, 'drop_point 2');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D6-R3', CURRENT_DATE, 6, 14, 2, 3, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 1, 'gudang 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 2, 'drop_point', 2, 'drop_point 2');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D15-R3', CURRENT_DATE, 15, 3, 2, 3, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 1, 'gudang 1');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 2, 'drop_point', 2, 'drop_point 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 3, 'drop_point', 2, 'drop_point 2');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D11-R2', CURRENT_DATE, 11, 9, 3, 2, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 2, 'gudang 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 2, 'drop_point', 3, 'drop_point 3');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D11-R3', CURRENT_DATE, 11, 9, 3, 3, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 3, 'gudang 3');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 2, 'gudang', 2, 'gudang 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 3, 'drop_point', 3, 'drop_point 3');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D10-R4', CURRENT_DATE, 10, 9, 3, 4, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 2, 'gudang 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 2, 'drop_point', 3, 'drop_point 3');

END $$;

DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('TR-20260808-D10-R1', CURRENT_DATE, 10, 9, 3, 1, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 1, 'gudang', 3, 'gudang 3');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_gudang, keterangan)
    VALUES (new_ritase_id, 2, 'gudang', 2, 'gudang 2');


    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, id_drop_point, keterangan)
    VALUES (new_ritase_id, 3, 'drop_point', 3, 'drop_point 3');

END $$;
COMMIT;