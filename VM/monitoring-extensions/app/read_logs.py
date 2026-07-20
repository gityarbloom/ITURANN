import json
from google.cloud import storage
from google.cloud.exceptions import NotFound

def read_json_from_bucket(bucket_name, blob_name):
    print(f"מתחבר לבאקט: {bucket_name} כדי לקרוא את {blob_name}...")
    
    try:
        # בגלל ה-ADC, אין צורך להעביר נתיב לקובץ מפתחות. 
        # הספרייה תדע לבד לפנות ל-Metadata Server של ה-VM.
        storage_client = storage.Client()
        
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        
        # הורדת תוכן הקובץ כטקסט
        file_content = blob.download_as_text()
        
        # טעינה כ-JSON
        data = json.loads(file_content)
        return data

    except NotFound:
        print(f"שגיאה: הבאקט או הקובץ לא נמצאו.")
        return None
    except Exception as e:
        print(f"שגיאה בתקשורת מול ה-Bucket: {e}")
        return None