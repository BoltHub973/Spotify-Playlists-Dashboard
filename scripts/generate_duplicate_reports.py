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

# Process each CSV file
current_dir = os.path.dirname(os.path.abspath(__file__))
data_csv_dir = os.path.abspath(os.path.join(current_dir, "..", "data", "csv"))
data_archived_dir = os.path.abspath(os.path.join(current_dir, "..", "data", "archived"))

csv_configs = [
    {
        "input_file": os.path.join(data_csv_dir, "Playlists to Display.csv"),
        "output_file": os.path.join(data_archived_dir, "Playlists Duplicates.csv"),
        "dashboard_col": "Dashboard Name",
        "spotify_col": "Spotify Playlist Name"
    },
    {
        "input_file": os.path.join(data_csv_dir, "Tracker to Display.csv"),
        "output_file": os.path.join(data_archived_dir, "Tracker Duplicates.csv"),
        "dashboard_col": "Dashboard Name",
        "spotify_col": "Spotify Playlist Name"
    }
]

for config in csv_configs:
    print(f"\nProcessing {config['input_file']}...")
    
    try:
        with open(config['input_file'], 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            issues_found = []
            
            for row in reader:
                spotify_name = row.get(config['spotify_col'], "").strip()
                
                # Skip dividers
                if spotify_name in ["DIVIDER", "LINE BREAK"]:
                    continue
                
                # Check if this playlist has duplicates
                if spotify_name in duplicates:
                    dashboard_name = row.get(config['dashboard_col'], "").strip()
                    duplicate_ids = duplicates[spotify_name]
                    
                    # Create a row with all duplicate IDs
                    issue_row = {
                        "Dashboard Name": dashboard_name,
                        "Spotify Playlist Name": spotify_name,
                        "Number of Duplicates": len(duplicate_ids)
                    }
                    
                    # Add each duplicate as a separate column
                    for i, pid in enumerate(duplicate_ids, 1):
                        issue_row[f"Playlist ID {i}"] = pid
                        issue_row[f"Playlist URL {i}"] = f"https://open.spotify.com/playlist/{pid}"
                    
                    issues_found.append(issue_row)
        
        if issues_found:
            # Write to output CSV
            with open(config['output_file'], 'w', newline='', encoding='utf-8') as f:
                # Determine fieldnames based on max number of duplicates
                max_duplicates = max(row['Number of Duplicates'] for row in issues_found)
                fieldnames = ["Dashboard Name", "Spotify Playlist Name", "Number of Duplicates"]
                for i in range(1, max_duplicates + 1):
                    fieldnames.append(f"Playlist ID {i}")
                    fieldnames.append(f"Playlist URL {i}")
                
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(issues_found)
            
            print(f"  ✅ Created {config['output_file']} with {len(issues_found)} duplicate issues")
        else:
            print(f"  ℹ️  No duplicates found, skipping {config['output_file']}")
            
    except Exception as e:
        print(f"  ❌ Error processing {config['input_file']}: {e}")

print("\n✅ Done!")
