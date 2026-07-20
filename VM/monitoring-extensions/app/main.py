import os
import json
from read_logs import read_json_from_bucket


if __name__ == "__main__":
    # מומלץ להעביר את השמות כמשתני סביבה (Environment Variables)
    BUCKET = os.getenv("BUCKET_NAME", "my-grafana-dashboards-bucket")
    BLOB = os.getenv("DASHBOARD_FILE_NAME", "dashboard.json")
    
    config_data = read_json_from_bucket(BUCKET, BLOB)
    
    if config_data:
        print("הקובץ נקרא בהצלחה! תוכן חלקי:")
        print(json.dumps(config_data, indent=2)[:500]) # מדפיס רק את ה-500 תווים הראשונים
        