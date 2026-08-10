import pandas as pd
import sys

# Ensure UTF-8 output
sys.stdout.reconfigure(encoding='utf-8')

try:
    xl = pd.ExcelFile('jadwal_rit_whiteboard.xlsx')
    print("Sheets available:", xl.sheet_names)
    
    df = pd.read_excel('jadwal_rit_whiteboard.xlsx', sheet_name='Jadwal Rit')
    print("\n--- Sheet: Jadwal Rit ---")
    print(df.to_string())
except Exception as e:
    print(f"Error: {e}")
