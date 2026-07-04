import os
import sys
import datetime
from dotenv import load_dotenv
from garminconnect import Garmin

# FORCE .env location to be the exact same directory where this script sits
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(SCRIPT_DIR, ".env")
load_dotenv(dotenv_path=ENV_PATH)

# ----------------- CONFIGURATION -----------------
GARMIN_EMAIL = os.environ.get("GARMIN_EMAIL")
GARMIN_PASSWORD = os.environ.get("GARMIN_PASSWORD")
# Download files straight into the current terminal execution directory
OUTPUT_DIR = os.getcwd() 
# Path where Garmin session tokens are securely archived to bypass MFA [754]
TOKEN_STORE_DIR = os.path.expanduser("~/.garminconnect")
# -------------------------------------------------

def get_mfa_code():
    print("\n🔒 Multi-Factor Authentication (MFA) is required by Garmin.")
    code = input("Enter the MFA verification code sent to your phone/email: ")
    return code.strip()

def download_activities_for_date():
    if not GARMIN_EMAIL or not GARMIN_PASSWORD:
        print("❌ Error: Missing credentials in configuration file.")
        print(f"Please check that your '.env' file exists in: {SCRIPT_DIR}")
        return

    # Parse command line argument or fallback to current local date
    if len(sys.argv) > 1:
        date_input = sys.argv[1]
        try:
            target_dt = datetime.datetime.strptime(date_input, "%Y-%m-%d").date()
            print(f"🎯 Target date parsed from command line: {target_dt}")
        except ValueError:
            print(f"❌ Error: Invalid date format '{date_input}'. Use YYYY-MM-DD.")
            return
    else:
        target_dt = datetime.date.today()
        print(f"📅 No date argument provided. Defaulting to today's date: {target_dt}")

    print("Initializing Headless Garmin Client...")
    client = Garmin(GARMIN_EMAIL, GARMIN_PASSWORD, prompt_mfa=get_mfa_code)
    
    try:
        # Pass TOKEN_STORE_DIR to check for cached logins and skip MFA [474, 715]
        client.login(TOKEN_STORE_DIR)
        print("Successfully authenticated (Used token storage if available).")
    except Exception as e:
        print(f"Login failed: {e}")
        return

    print("Searching for recent activities...")
    activities = client.get_activities(0, 30)

    matching_activities = []
    for act in activities:
        start_time_str = act.get("startTimeLocal")
        if start_time_str:
            act_date = datetime.datetime.strptime(start_time_str, "%Y-%m-%d %H:%M:%S").date()
            if act_date == target_dt:
                matching_activities.append(act)

    if not matching_activities:
        print(f"ℹ️ No activities found matching date: {target_dt}")
        return

    print(f"✅ Found {len(matching_activities)} activity/activities on {target_dt}. Syncing to: {OUTPUT_DIR}")

    for act in matching_activities:
        act_id = act["activityId"]
        act_name = act.get("activityName", "Activity").replace(" ", "_")
        print(f"\nProcessing Activity ID: {act_id} ({act_name})")

        # 1. Download GPX Format
        try:
            print(" -> Downloading GPX...")
            gpx_data = client.download_activity(act_id, dl_fmt=Garmin.ActivityDownloadFormat.GPX)
            with open(os.path.join(OUTPUT_DIR, f"{act_id}_{act_name}.gpx"), "wb") as f:
                f.write(gpx_data)
        except Exception as e:
            print(f"    Failed to download GPX: {e}")

        # 2. Download TCX Format
        try:
            print(" -> Downloading TCX...")
            tcx_data = client.download_activity(act_id, dl_fmt=Garmin.ActivityDownloadFormat.TCX)
            with open(os.path.join(OUTPUT_DIR, f"{act_id}_{act_name}.tcx"), "wb") as f:
                f.write(tcx_data)
        except Exception as e:
            print(f"    Failed to download TCX: {e}")

        # 3. Download Original FIT Zip
        try:
            print(" -> Downloading Original FIT Zip...")
            zip_data = client.download_activity(act_id, dl_fmt=Garmin.ActivityDownloadFormat.ORIGINAL)
            with open(os.path.join(OUTPUT_DIR, f"{act_id}_{act_name}_original.zip"), "wb") as f:
                f.write(zip_data)
        except Exception as e:
            print(f"    Failed to download Original ZIP: {e}")

    print(f"\n🎉 Process finished. Files dumped directly to active directory folder.")

if __name__ == "__main__":
    download_activities_for_date()
