import pandas as pd
import re

# Flexible parsing for stop string
def parse_stop(stop_str):
    stop_str = stop_str.strip().lower()
    
    # Check drop point first
    if 'drop' in stop_str and 'point' in stop_str:
        m = re.search(r'(?:id\s+)?drop\s*point\s*(\d+)', stop_str)
        if m: return ('drop_point', int(m.group(1)))
    # Check seller
    elif 'seller' in stop_str:
        m = re.search(r'(?:id\s+)?seller\s*(\d+)', stop_str)
        if m: return ('seller', int(m.group(1)))
    # Check gudang
    elif 'gudang' in stop_str:
        m = re.search(r'(?:id\s+)?gudang\s*(\d+)', stop_str)
        if m: return ('gudang', int(m.group(1)))
        
    return None

try:
    df = pd.read_excel('jadwal_rit_whiteboard.xlsx', sheet_name='Jadwal Rit')
    
    sql_statements = []
    sql_statements.append("BEGIN;")
    sql_statements.append("INSERT INTO gudang (id_gudang, nama_gudang) VALUES (3, 'Gudang 3') ON CONFLICT (id_gudang) DO NOTHING;")
    sql_statements.append("INSERT INTO drop_point (id_drop_point, kode_dp, nama_drop_point, status) VALUES (3, 'DP-003', 'J&T Express Gateway SEG777', 'aktif') ON CONFLICT (id_drop_point) DO NOTHING;")
    sql_statements.append("DELETE FROM armada_tracking WHERE id_ritase IN (SELECT id_ritase FROM ritase WHERE tanggal = (now() AT TIME ZONE 'Asia/Jakarta')::date OR tanggal IS NULL);")
    sql_statements.append("DELETE FROM ritase_event WHERE id_ritase IN (SELECT id_ritase FROM ritase WHERE tanggal = (now() AT TIME ZONE 'Asia/Jakarta')::date OR tanggal IS NULL);")
    sql_statements.append("DELETE FROM ritase_stop WHERE id_ritase IN (SELECT id_ritase FROM ritase WHERE tanggal = (now() AT TIME ZONE 'Asia/Jakarta')::date OR tanggal IS NULL);")
    sql_statements.append("DELETE FROM ritase WHERE tanggal = (now() AT TIME ZONE 'Asia/Jakarta')::date OR tanggal IS NULL;")
    
    generated_count = 0
    for idx, row in df.iterrows():
        if pd.isna(row.iloc[1]) or pd.isna(row.iloc[2]) or pd.isna(row.iloc[3]):
            continue
            
        driver_val = str(row.iloc[1])
        kendaraan_val = str(row.iloc[2])
        rute_val = str(row.iloc[3])
        ritase_val = str(row.iloc[4])
        catatan = str(row.iloc[5]) if not pd.isna(row.iloc[5]) else ""
        
        if not driver_val.isdigit() or not kendaraan_val.isdigit():
            continue
            
        id_driver = int(driver_val)
        id_kendaraan = int(kendaraan_val)
        
        ritase_num = 1
        m_rit = re.search(r'\d+', ritase_val)
        if m_rit:
            ritase_num = int(m_rit.group(0))
        
        if "perlu dicek" in catatan.lower() and not "pga2" in rute_val.lower():
             continue
             
        stops_str = rute_val.split('→')
        parsed_stops = []
        for s in stops_str:
            parsed = parse_stop(s)
            if parsed:
                parsed_stops.append(parsed)
            else:
                print(f"Skipping row {idx} (Driver {id_driver} Rit {ritase_num}) due to unparsed stop: '{s}'")
                parsed_stops = []
                break
                
        if len(parsed_stops) == 0:
            continue
            
        id_drop_point = 1
        for s in reversed(parsed_stops):
            if s[0] == 'drop_point':
                id_drop_point = s[1]
                break
                
        kode_ritase = f"TR-20260808-D{id_driver}-R{ritase_num}"
        
        sql_statements.append(f"""
DO $$
DECLARE
    new_ritase_id INT;
BEGIN
    INSERT INTO ritase (kode_ritase, tanggal, id_driver, id_kendaraan, id_drop_point, ritase_ke, status)
    VALUES ('{kode_ritase}', (now() AT TIME ZONE 'Asia/Jakarta')::date, {id_driver}, {id_kendaraan}, {id_drop_point}, {ritase_num}, 'direncanakan')
    RETURNING id_ritase INTO new_ritase_id;
""")
        
        for i, stop in enumerate(parsed_stops):
            urutan = i + 1
            jenis = stop[0]
            id_lokasi = stop[1]
            
            kolom = ""
            if jenis == "gudang": kolom = "id_gudang"
            elif jenis == "seller": kolom = "id_seller"
            elif jenis == "drop_point": kolom = "id_drop_point"
            
            sql_statements.append(f"""
    INSERT INTO ritase_stop (id_ritase, urutan, jenis_stop, {kolom}, keterangan)
    VALUES (new_ritase_id, {urutan}, '{jenis}', {id_lokasi}, '{jenis} {id_lokasi}');
""")
            
        sql_statements.append("END $$;")
        generated_count += 1

    sql_statements.append("COMMIT;")
    
    with open('seed_jadwal.sql', 'w') as f:
        f.write("\n".join(sql_statements))
        
    print(f"Generated seed_jadwal.sql successfully with {generated_count} ritase assignments.")
except Exception as e:
    print(f"Error: {e}")
