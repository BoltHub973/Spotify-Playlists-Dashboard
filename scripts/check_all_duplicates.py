import os
import sys
import spotipy
from spotipy.oauth2 import SpotifyOAuth
from spotipy.exceptions import SpotifyOauthError
from dotenv import load_dotenv
import csv

load_dotenv()


def handle_expired_login(sp):
    """Spotify refresh tokens now expire ~6 months after authorization. When the
    token endpoint returns 400 invalid_grant, spotipy raises SpotifyOauthError.
    Clear the dead token and ask the user to re-run so a fresh browser login runs."""
    print("\n⚠️  Your Spotify login has expired (refresh tokens now expire ~6 months after authorization).")
    try:
        cache_path = sp.auth_manager.cache_handler.cache_path
        if os.path.exists(cache_path):
            os.remove(cache_path)
            print(f"Cleared the expired token ({cache_path}).")
    except Exception:
        pass
    print("Re-run this script to sign in again.")
    sys.exit(1)


sp = spotipy.Spotify(auth_manager=SpotifyOAuth(scope='playlist-read-private playlist-read-collaborative'))

# Get all user playlists
print("Fetching all playlists...")
try:
    results = sp.current_user_playlists(limit=50)
    playlists = results['items']
    while results['next']:
        results = sp.next(results)
        playlists.extend(results['items'])
except SpotifyOauthError:
    handle_expired_login(sp)

print(f"Total playlists: {len(playlists)}\n")

# Create a map of playlist names to their IDs
playlist_name_map = {}
for p in playlists:
    name = p['name']
    if name not in playlist_name_map:
        playlist_name_map[name] = []
    playlist_name_map[name].append(p['id'])

# Find duplicates
duplicates = {name: ids for name, ids in playlist_name_map.items() if len(ids) > 1}

print(f"Found {len(duplicates)} duplicate playlist names:\n")
for name, ids in duplicates.items():
    print(f"'{name}' has {len(ids)} copies:")
    for pid in ids:
        print(f"  - {pid}")
    print()

# Now check each CSV file
current_dir = os.path.dirname(os.path.abspath(__file__))
data_csv_dir = os.path.abspath(os.path.join(current_dir, "..", "data", "csv"))

csv_files = [
    os.path.join(data_csv_dir, "Playlists to Display.csv"),
    os.path.join(data_csv_dir, "Tracker to Display.csv"), 
    os.path.join(data_csv_dir, "Queue to Display.csv")
]

print("\n" + "="*80)
print("CHECKING CSV FILES FOR DUPLICATE ISSUES")
print("="*80 + "\n")

for csv_file in csv_files:
    print(f"\n📄 Checking {csv_file}...")
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            issues_found = []
            
            for row in reader:
                # Handle different column names
                if "Spotify Playlist Name" in row:
                    spotify_name = row["Spotify Playlist Name"].strip()
                elif "spotify_name" in row:
                    spotify_name = row["spotify_name"].strip()
                else:
                    continue
                
                # Skip dividers
                if spotify_name in ["DIVIDER", "LINE BREAK"]:
                    continue
                
                # Check if this playlist has duplicates
                if spotify_name in duplicates:
                    dashboard_name = row.get("Dashboard Name") or row.get("Name") or row.get("name", "")
                    issues_found.append({
                        "dashboard_name": dashboard_name.strip(),
                        "spotify_name": spotify_name,
                        "duplicate_ids": duplicates[spotify_name]
                    })
            
            if issues_found:
                print(f"  ⚠️  Found {len(issues_found)} potential duplicate issues:")
                for issue in issues_found:
                    print(f"\n    Dashboard Name: '{issue['dashboard_name']}'")
                    print(f"    Spotify Playlist: '{issue['spotify_name']}'")
                    print(f"    {len(issue['duplicate_ids'])} copies found:")
                    for pid in issue['duplicate_ids']:
                        print(f"      - https://open.spotify.com/playlist/{pid}")
            else:
                print(f"  ✅ No duplicate issues found")
                
    except Exception as e:
        print(f"  ❌ Error reading file: {e}")

print("\n" + "="*80)
