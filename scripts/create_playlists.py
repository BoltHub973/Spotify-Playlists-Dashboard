import csv
import os
import sys
from dotenv import load_dotenv

load_dotenv()

try:
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth
    from spotipy.exceptions import SpotifyOauthError
except ImportError:
    print("Error: 'spotipy' library is not installed.")
    print("Please install it using: pip install spotipy")
    sys.exit(1)

# Configuration
CSV_FILE = "../data/archived/Playlists to Create - Queues.csv"
SCOPE = "playlist-modify-public"
REDIRECT_URI = "http://127.0.0.1:8888/callback"

def get_credentials():
    """Gets Spotify credentials from environment variables or user input."""
    client_id = os.environ.get("SPOTIPY_CLIENT_ID")
    client_secret = os.environ.get("SPOTIPY_CLIENT_SECRET")
    redirect_uri = os.environ.get("SPOTIPY_REDIRECT_URI", REDIRECT_URI)

    if not client_id:
        client_id = input("Enter your Spotify Client ID: ").strip()
    if not client_secret:
        client_secret = input("Enter your Spotify Client Secret: ").strip()
    
    return client_id, client_secret, redirect_uri

def read_playlists_from_csv(filepath):
    """Reads playlist names from the first column of the CSV file."""
    playlists = []
    try:
        with open(filepath, mode='r', encoding='utf-8') as f:
            reader = csv.reader(f)
            for row in reader:
                if row:
                    playlists.append(row[0].strip())
    except FileNotFoundError:
        print(f"Error: CSV file '{filepath}' not found.")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading CSV: {e}")
        sys.exit(1)
    return playlists

def main():
    print("--- Spotify Playlist Creator ---")
    
    # Check for CSV file
    csv_path = os.path.join(os.path.dirname(__file__), CSV_FILE)
    if not os.path.exists(csv_path):
        print(f"Error: Could not find {csv_path}")
        return

    # Get Credentials
    client_id, client_secret, redirect_uri = get_credentials()
    
    # Authenticate
    try:
        sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
            client_id=client_id,
            client_secret=client_secret,
            redirect_uri=redirect_uri,
            scope=SCOPE
        ))
        user_id = sp.current_user()['id']
        print(f"Authenticated as user: {user_id}")
    except SpotifyOauthError as e:
        # Refresh tokens now expire ~6 months after authorization (400 invalid_grant).
        print("\n⚠️  Your Spotify login has expired (refresh tokens now expire ~6 months after authorization).")
        try:
            cache_path = sp.auth_manager.cache_handler.cache_path
            if os.path.exists(cache_path):
                os.remove(cache_path)
                print(f"Cleared the expired token ({cache_path}).")
        except Exception:
            pass
        print("Re-run this script to sign in again.")
        return
    except Exception as e:
        print(f"Authentication failed: {e}")
        print("Please check your credentials and try again.")
        return

    # Read Playlists
    playlists_to_create = read_playlists_from_csv(csv_path)
    print(f"Found {len(playlists_to_create)} playlists to create.")
    
    if not playlists_to_create:
        print("No playlists found in CSV.")
        return

    # confirm = input(f"Are you sure you want to create {len(playlists_to_create)} playlists? (y/n): ")
    # if confirm.lower() != 'y':
    #     print("Operation cancelled.")
    #     return

    # Create Playlists
    created_count = 0
    for name in playlists_to_create:
        if not name:
            continue
            
        try:
            sp.user_playlist_create(user_id, name, public=True)
            print(f"Created playlist: {name}")
            created_count += 1
        except Exception as e:
            print(f"Failed to create playlist '{name}': {e}")

    print(f"\nDone. Created {created_count} playlists.")

if __name__ == "__main__":
    main()
